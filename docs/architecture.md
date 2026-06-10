# zypher Architecture

## Error Propagation Convention

All zypher subsystem errors are namespaced under `ZypherError` (defined in `src/errors.zig`).

### Rules

1. **Use `ZypherError!T` for all public API return types.** Never use ad-hoc error sets.
2. **Propagate with `try`.** Never swallow errors silently. If recovery is needed, use `catch |err|` with explicit handling.
3. **Convert external errors at subsystem boundaries.** When a subsystem calls into `std`, SQLite, or any external API, catch the external error and map it to the appropriate `ZypherError` variant:

   ```zig
   fn connectDb(path: []const u8) ZypherError!*Db {
       const db = sqlite.open(path) catch return error.DbConnectionFailed;
       return db;
   }
   ```

4. **Log before returning errors.** At subsystem boundaries, log the error with context before propagating:

   ```zig
   fn handleRequest(req: *const Request) ZypherError!Response {
       const result = parseBody(req) catch |err| {
           log.writeLog(.err, "request", "parse failed");
           return err; // already a ZypherError
       };
       // ...
   }
   ```

5. **Never use `unreachable` for error conditions.** `unreachable` is only for logically impossible states. Use `error.Xyz` for anything that can fail at runtime.

6. **Error-to-string mapping.** Use `errors.errorToString(err)` for user-facing messages. The mapping is exhaustive and maintained alongside the error set.

### Error Categories

| Category | Prefix | Example |
|---|---|---|
| Core / HTTP | (none) | `BadRequest`, `NotFound` |
| Router | (none) | `InvalidRoutePattern`, `AmbiguousRoute` |
| Middleware | (none) | `CsrfValidationFailed`, `CorsBlocked` |
| Template | (none) | `TemplateNotFound`, `TemplateSyntaxError` |
| ORM / Database | `Db` | `DbConnectionFailed`, `DbQueryFailed` |
| Forms / Validation | `Field` / `Invalid` | `FieldRequired`, `InvalidEmail` |
| Auth | (none) | `AuthenticationFailed`, `SessionInvalid` |
| Admin | `Admin` | `AdminModelNotRegistered` |
| CLI | (none) | `UnknownCommand`, `InvalidArguments` |

---

## Allocation Rules

> zypher is designed for minimal and predictable allocations. Callers always know what allocates.

### Design Principles

1. **All allocation contexts require an explicit `Allocator` parameter.** No global allocators, no implicit allocations.
2. **Hot path allocations are forbidden.** Route dispatch, header lookup, path matching — all zero-alloc.
3. **Callers own deallocation.** If a function returns allocated memory, the caller is responsible for freeing it.

### Known Allocation Points (by subsystem)

#### Core (`src/core/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `Request.parse()` | Body buffer, header map entries, query params map, form data, cookie map | Freed by `Request.deinit()` | `max_body_size` caps the body buffer |
| `Response.init()` | Header map | Freed by `Response.deinit()` | |
| `Response.header()` | Copies both key and value | Freed by `Response.deinit()` | Zero-alloc if key already exists (replaces value) |
| `Response.text/html/json()` | Duplicates body content | Freed by `Response.deinit()` | |
| `Response.setCookie()` | Builds Set-Cookie header string | Freed by `Response.deinit()` | |
| `Response.send()` | Status code + Content-Length as formatted strings | Stack-allocated (fixed buffers) | Zero-alloc |
| `Server.listenAndServe()` | Per-connection request/response, thread-local scratch | Per-connection: freed after response sent | |

#### Router (`src/router/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `Router.dispatch()` | Nothing on match path | — | Uses fixed-size `RouteParams` (max 16 params, no heap) |
| `Route.matchPath()` | Nothing | — | Returns slices into the input path |
| `RouteParams.put()` | Nothing | — | Stores pointers into request path |
| `RouteParams.getAs()` | Parsed integers on stack | — | Zero-alloc |

#### Middleware (`src/middleware/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| Logger middleware | Nothing (just logging) | — | |
| CORS middleware | Nothing (compares config at comptime) | — | |
| CSRF middleware | Nothing (fixed token string) | — | |
| Rate limiter | Window counter map entries | Per-window: freed on window expiry | O(active IPs) |
| Session middleware | Session data strings | Per-request: freed by session store | |
| Static file middleware | File contents into response body | Freed by Response.deinit() | |
| Compression middleware | Gzip-compressed body buffer | Per-response: freed by Response.deinit() | |
| Security headers middleware | Nothing (fixed header strings) | — | |

#### Template Engine (`src/template/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `Template.fromSource()` | AST node list, token list | Freed by `Template.deinit()` | One-time parse cost; cached by TemplateEngine |
| `TemplateEngine.load()` | Parsed template in cache | Lifetime of engine | Cache lives until `engine.deinit()` |
| `Template.render()` | Rendered output buffer | Per-render: freed by caller's writer | |
| `TemplateEngine.render()` | Rendered output buffer | Per-render: freed by caller's writer | |
| Filter functions (upper/lower/etc.) | Transformed string | Per-filter: caller frees via `FilterResult.deinit()` | |

#### ORM (`src/orm/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `sqlite.Db.open()` | Connection handle wrapper | Freed by `Db.close()` | |
| `sqlite.Db.prepare()` | Statement handle wrapper | Freed by `Statement.finalize()` | |
| `query.getById()` | Row with copied text fields | Caller frees via `freeRow()` | |
| `query.all()` / `query.filter()` | ArrayList of rows + text fields | Caller frees via `freeRow()` + `deinit()` | |
| `query.filterLimitOffset()` | ArrayList of rows + text fields | Caller frees via `freeRow()` + `deinit()` | |
| `query.filterOrderLimitOffset()` | ArrayList of rows + SQL string | Caller frees via `freeRow()` + `deinit()` | |
| `query.first()` | Single row or null | Caller frees via `freeRow()` | |
| `query.count()` | Nothing (SQLite returns integer) | — | Zero-alloc |
| `migration.migrate()` / `rollback()` | Per-migration status strings | Freed on store deinit | |

#### Forms (`src/forms/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `Form.bind()` | Values map + errors map | Freed by `BoundForm.deinit()` | |
| `BoundForm.validate()` | Error map entries | Freed by `BoundForm.deinit()` | |
| `BoundForm.cleanedData()` | Nothing (returns slices into values map) | Valid until values map is freed | |

#### Auth (`src/auth/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `password.hash()` | Hash string (salt + hash hex) | Caller frees | |
| `password.verify()` | Nothing on success | — | |
| `SessionStore.init()` | Internal HashMap | Freed by `deinit()` | |
| `Session.put()` | Key + value strings | Freed by `SessionStore.deinit()` | |
| `User.init()` | Username + password_hash strings | Freed by `User.deinit()` | |

#### CLI (`src/cli/`)

| Function | What Allocates | Memory Lifetime | Notes |
|---|---|---|---|
| `new` command | Directory strings, file contents | Freed on scope exit | |
| `runserver` | Server config | Server lifetime | |
| `migrate` / `makemigrations` | SQL strings, file paths | Per-command: freed before return | |
| `createsuperuser` | User credentials, hash | Per-command: freed before return | |
| `shell` | Expression results | Per-evaluation: freed before next prompt | |

### Hot Path — Zero-Allocation Guarantee

The following operations **must never allocate** on the hot path:

- HTTP method parsing
- URL path matching (`Route.matchPath`)
- Router dispatch (`Router.dispatch`)
- Header lookup (`Request.header`)
- Query parameter lookup (`Request.queryParam`)
- Cookie lookup (`Request.cookie`)
- Response status code setting
- Response header writing (for already-owned keys)
- Logging (stdlib scoped logger is allocation-free)

These are enforced by regression tests using `std.testing.allocator` for allocation detection.

---

## Subsystem Map

```
┌───────────────────────────────────────────────────────────────┐
│                        zypher (Framework)                     │
│                                                               │
│  ┌──────────┐   ┌──────────┐   ┌────────────┐                │
│  │   Core   │──▶│  Router  │──▶│ Middleware │                │
│  │ Request  │   │  Route   │   │   Chain    │                │
│  │ Response │   │  Params  │   │  Logger    │                │
│  │  Server  │   │          │   │  CORS      │                │
│  │   App    │   │          │   │  CSRF      │                │
│  └──────────┘   └──────────┘   │  RateLimit │                │
│                                │  Static    │                │
│  ┌────────────┐                │  Compress  │                │
│  │  Template  │                │  Session   │                │
│  │  Engine    │                │  Security  │                │
│  │  Lexer     │                └─────┬──────┘                │
│  │  Parser    │                      │                       │
│  │  Renderer  │                      ▼                       │
│  │  Filters   │               ┌──────────────┐              │
│  └────────────┘               │   Handlers   │              │
│                               │  (User Code) │              │
│  ┌──────────┐   ┌──────────┐  └──────────────┘              │
│  │   ORM    │   │  Forms   │                                │
│  │  SQLite  │   │  Field   │   ┌─────────────┐              │
│  │  Schema  │   │  Valid.  │   │    Auth     │              │
│  │  Query   │   │  Engine  │   │  Session    │              │
│  │ Migrate  │   │          │   │  Password   │              │
│  └──────────┘   └──────────┘   │  User/Guard │              │
│                                │  Auth Views │              │
│  ┌──────────────────────┐      └─────────────┘              │
│  │  Admin Panel         │                                    │
│  │  Registry + Views    │   ┌────────────────────┐          │
│  │  Templates (inline)  │   │  CLI Tooling       │          │
│  └──────────────────────┘   │  new/runserver     │          │
│                              │  migrate/makemig.  │          │
│                              │  createsuperuser   │          │
│                              │  shell             │          │
│                              └────────────────────┘          │
└───────────────────────────────────────────────────────────────┘
```

**Data flow (request lifecycle):**
1. `Server` accepts TCP connection → parses HTTP → creates `Request`
2. `App.run` calls middleware chain
3. Middleware chain (order: Logger → CORS → CSRF → RateLimit → Static → Session → Compression → SecurityHeaders)
4. Terminal middleware calls `Router.dispatch`
5. Router matches path, extracts params, calls handler
6. Handler reads request, may query DB (ORM), render templates, validate forms
7. Handler writes response (status, headers, body)
8. Response is serialized to wire format and sent
9. Request/Response are deallocated per connection

**Data flow (ORM interaction):**
- Handler → form bind/validate → ORM create/filter/save → response
- Auth middleware → session store → user guards → handler

**Data flow (template rendering):**
- Handler → TemplateEngine.load (if uncached) → Template.render → Response.html
