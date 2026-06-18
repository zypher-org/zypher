# Zypher API Reference

This directory contains the Zypher web framework API reference documentation.

## Quick Start
```sh
zig build
export PATH="$PWD/zig-out/bin:$PATH"
zypher new examples/blog --template mvc
zypher run examples/blog
zypher doc
zypher doc-user examples/blog
```

## API Modules

### Core (`zypher.core.*`)
- `Method` — HTTP method enum (get, post, put, patch, delete, options, head)
- `SameSite` — SameSite cookie attribute enum (Strict, Lax, None)
- `Cookie` — Set-Cookie configuration struct
- `Server` — low-level HTTP server with Config, buildRequest, listenAndServe, shutdown
- `Server.HandlerFn` — handler function type `*const fn (*Request, *Response) void`
- `App` — high-level application struct wrapping server, handlers, router, middleware, database
- `Request` — incoming HTTP request with method, path, query, headers, body, files, params, user, cookies, file streaming
- `Response` — outgoing HTTP response with status, headers, body, file_body, cookies, chunked streaming, serialization
- `Context` — request-scoped context struct

### Router (`zypher.router.*`)
- `Route` — route definition with method, pattern, handler; supports named params, typed params, wildcards
- `RouteParams` — zero-allocation URL parameter storage (max 16 params)
- `Router` — comptime route table with runtime dispatch; supports groups, specificity scoring, 405 Allow headers

### Middleware (`zypher.middleware.*`)
- `Chain` — comptime middleware pipeline with fully unrolled dispatch
- `logger.middleware` — request logging with method, path, status, duration
- `cors.middleware` / `cors.middlewareWith(config)` — CORS with configurable origins, methods, headers, preflight
- `csrf.middleware` — CSRF protection via session tokens
- `rate_limit.middlewareWith(config)` — fixed window rate limiter per IP
- `static.middlewareWith(config)` — static file serving with MIME detection, ETag/304, Range/206
- `compress.middleware` — gzip buffered response compression
- `session.middleware` — session load/save middleware
- `security_headers.middleware` / `security_headers.configure(opts)` — security header injection
- `recovery.middleware` — recovery middleware placeholder

### Template (`zypher.template.*`)
- `lexer.Lexer` — template source tokenizer
- `parser.Parser` — template AST builder
- `renderer.Template` — parsed template with render, extends, include, if, for
- `renderer.TemplateEngine` — template cache with load/render
- `core.Context` — template variable context (string-keyed Value map)
- `renderer.Value` — template value union (string, int, float, bool, list, map, null)
- `filters` — built-in filters (upper, lower, capitalize, title, trim, length, reverse, escape, safe, join, truncate, default, date)

### ORM (`zypher.orm.*`)
- `sqlite.Db` — SQLite connection wrapper (open, close, exec, prepare, lastInsertRowId, changes)
- `sqlite.Stmt` — prepared statement (bind, step, column, reset, finalize)
- `sqlite.Value` — SQL value union (int, float, text, null)
- `schema.Model(table, fields)` / `schema.Field(name, kind, opts)` — comptime model/field definitions with SQL generation
- `query.create`, `query.getById`, `query.all`, `query.filter`, `query.updateById`, `query.deleteById`, `query.save`, `query.count`, `query.first` — runtime CRUD
- `QuerySet` — chainable query builder (filterBy, orderBy, limit, offset, exec)
- `migration.MigrationRunner` — schema migration runner with up/down SQL and history tracking

### Forms (`zypher.forms.*`)
- `form.FieldKind` — text, integer, boolean, file
- `form.FieldDef` — field definition with name, kind, required, validator
- `form.Form(name, Fields)` — comptime form generation with bind, bindRequest, BoundForm
- `form.BoundForm` — bound form with getValue, validate, cleanedData, csrfField, csrfFieldForRequest
- `validators` — built-in validators (email, minLength, maxLength, matches, integer, url)

### Auth (`zypher.auth.*`)
- `session.SessionStore` — in-memory session store (create, save, getByHexId, destroyByHexId)
- `session.Session` — session with put, get, isExpired; 256-bit random IDs
- `password.hash` / `password.verify` — PBKDF2-HMAC-SHA256 hashing
- `user.User` — user model with init, authenticate, setRole, deactivate
- `user.loginRequired`, `user.superuserRequired` — auth middleware
- `user.loginView`, `user.logoutView`, `user.registerView` — built-in views

### Admin (`zypher.admin.*`)
- `AdminModelOptions` — per-model admin config (verbose_name_plural, list_per_page, etc.)
- `Registration(Model, opts)` — register a model for the admin
- `AdminSite(config)` — build a comptime admin site with CRUD routes
- `setDb`, `setEngine` — thread-local resource binding
- Auto-generated routes: list, add, create, change, update, confirm delete, delete
- Session-based access control requiring role=admin
- Template rendering with inline HTML fallback
- CSRF-protected mutations with audit logging

### CLI (`zypher.cli_runner.*`)
- `Runner` — CLI command dispatcher
- `RunserverConfig` — server configuration struct
- Commands: `new`, `templates`, `run`, `doc`, `doc-user`, `demo`, `runserver`, `migrate`, `makemigrations`, `createsuperuser`, `shell`, `help`
- Built-in scaffold templates (single-file, clean-arch, mvc, mvp + API variants)
- Superuser creation with password validation
- SQL migration generation and application
- Documentation server for framework and user code
