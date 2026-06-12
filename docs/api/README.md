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

### Core
- `Method` — HTTP method enum (get, post, put, patch, delete, options, head)
- `SameSite` — SameSite cookie attribute enum (Strict, Lax, None)
- `Cookie` — Set-Cookie configuration struct
- `Server` — low-level HTTP server with Config, buildRequest, listenAndServe, shutdown
- `Server.HandlerFn` — handler function type `*const fn (*Request, *Response) void`
- `App` — high-level application struct wrapping server, handlers, router, middleware, database
- `Request` — incoming HTTP request with method, path, query, headers, body, files, params, user, cookies
- `Response` — outgoing HTTP response with status, headers, body, cookies, chunked streaming, serialization

### Router
- `Route` — route definition with method, pattern, handler; supports named params, typed params, wildcards
- `RouteParams` — zero-allocation URL parameter storage (max 16 params)
- `Router` — comptime route table with runtime dispatch; supports groups, specificity scoring, 405 Allow headers

### Middleware
- `Chain` — comptime middleware pipeline with fully unrolled dispatch
- `Logger` — request logging with method, path, status, duration
- `CORS` — Cross-Origin Resource Sharing with configurable origins, methods, headers, preflight
- `CSRF` — Cross-Site Request Forgery protection via session tokens
- `RateLimit` — fixed window rate limiter per IP
- `Static` — static file serving with MIME detection, ETag/304, path traversal protection
- `Compress` — gzip response compression
- `Session` — session load/save middleware
- `SecurityHeaders` — security header injection (X-Content-Type-Options, X-Frame-Options, etc.)
- `Recovery` — recovery middleware placeholder

### Template
- `Lexer` — template source tokenizer
- `Parser` — template AST builder
- `Template` — parsed template with render, extends, include, if, for
- `TemplateEngine` — template cache with load/render
- `Context` — template variable context (string-keyed Value map)
- `Value` — template value union (string, int, float, bool, list, map, null)
- `Filters` — built-in filters (upper, lower, capitalize, title, trim, length, reverse, escape, safe, join, truncate, default, date)

### ORM
- `Db` — SQLite connection wrapper (open, close, exec, prepare, lastInsertRowId, changes)
- `Stmt` — prepared statement (bind, step, column, reset, finalize)
- `Value` — SQL value union (int, float, text, null)
- `Schema` — comptime model/field definitions with SQL generation
- `Query` — runtime CRUD operations (create, getById, all, filter, updateById, deleteById, save, count, first)
- `QuerySet` — chainable query builder (filterBy, orderBy, limit, offset, exec)
- `Migration` — schema migration runner with up/down SQL and history tracking

### Forms
- `FieldKind` — text, integer, boolean, file
- `FieldDef` — field definition with name, kind, required, validator
- `Form(name, Fields)` — comptime form generation with bind, bindRequest, BoundForm
- `BoundForm` — bound form with getValue, validate, cleanedData, csrfField, csrfFieldForRequest
- `Validators` — built-in validators (email, minLength, maxLength, matches, integer, url)

### Auth
- `SessionStore` — in-memory session store (create, save, getByHexId, destroyByHexId)
- `Session` — session with put, get, isExpired; 256-bit random IDs
- `Password` — PBKDF2-HMAC-SHA256 hashing (hash, verify)
- `User` — user model with init, authenticate, setRole, deactivate
- Auth middleware: `loginRequired`, `superuserRequired`
- Built-in views: `loginView`, `logoutView`, `registerView`

### Admin
- `AdminModelOptions` — per-model admin config (verbose_name_plural, list_per_page, etc.)
- `Registration(Model, opts)` — register a model for the admin
- `AdminSite(config)` — build a comptime admin site with CRUD routes
- `setDb`, `setEngine` — thread-local resource binding
- Auto-generated routes: list, add, create, change, update, confirm delete, delete
- Session-based access control requiring role=admin
- Template rendering with inline HTML fallback
- CSRF-protected mutations with audit logging

### CLI
- `Runner` — CLI command dispatcher
- `RunserverConfig` — server configuration struct
- Commands: `new`, `templates`, `run`, `doc`, `doc-user`, `demo`, `runserver`, `migrate`, `makemigrations`, `createsuperuser`, `shell`, `help`
- Built-in scaffold templates (single-file, clean-arch, mvc, mvp + API variants)
- Superuser creation with password validation
- SQL migration generation and application
- Documentation server for framework and user code
