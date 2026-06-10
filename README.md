# zypher

> **A batteries-included web framework, built the Zig way.**

zypher is a Django-inspired web framework written in **Zig**, designed for developers who want **clarity, control, and correctness** without sacrificing productivity.

It provides the full set of tools needed to build server-side web applications — routing, middleware, templates, ORM, authentication, and an admin panel — while staying true to Zig’s philosophy: **explicit over magic, compile-time over runtime, and simplicity over cleverness**.

---

## Why zypher?

Most web frameworks fall into one of two camps:
- *Minimal* frameworks that leave everything to you
- *Magical* frameworks that hide too much

zypher sits deliberately in the middle.

It gives you **batteries included**, but every abstraction is:
- Understandable
- Inspectable
- Replaceable

If you’ve ever wondered *“how does Django actually work under the hood?”*, zypher is built to answer that — in code.

---

## Design Philosophy

- **Explicit is better than implicit**
- **Compile-time correctness beats runtime surprises**
- **Security by default**
- **Minimal allocations, predictable performance**
- **One obvious way to do things**

zypher avoids runtime reflection and hidden global state. Instead, it uses Zig’s compile-time features to catch errors early and generate efficient code.

---

## Features (v1 scope)

- HTTP/1.1 server built on `std.http`
- Compile-time routing with typed URL parameters
- Middleware pipeline
- Function-based views / controllers
- Server-side template engine (auto-escaped HTML)
- ORM with compile-time SQL generation (SQLite)
- Database migrations
- Forms and input validation
- Authentication and session management
- Auto-generated admin panel
- CLI tooling for common tasks

---

## What zypher Is *Not*

zypher does **not** try to:
- Replace Django feature-for-feature
- Support every database or protocol
- Hide complexity through runtime magic
- Be async-first (yet)

The goal is **correctness, clarity, and learning value**, not maximum buzzwords.

---

## Quick Start

Build the local CLI once from the repository root:

```sh
zig build
export PATH="$PWD/zig-out/bin:$PATH"
zypher help
```

### Scaffolded App

Use the CLI when starting a new app:

```sh
zypher new examples/blog --template mvc
cd examples/blog
zypher createsuperuser --db blog.db
zypher run . --port 8080
```

`zypher new` accepts either a project name or a path. The built-in templates live in the root `templates/` directory:

- `single-file` — minimal one-file app
- `clean-arch` — domain/application/infrastructure/presentation split
- `mvc` — model/view/controller split
- `mvp` — model/view/presenter split

Use `--api` to scaffold the JSON API variant of any built-in style:

```sh
zypher new examples/books-api --template mvc --api
```

Third-party templates can be used with `--template-dir`:

```sh
zypher new apps/admin_tool --template custom --template-dir /path/to/templates
```

Generated templates include a `build.zig`, a runnable app, a sample managed ORM model, and an admin dashboard. `/admin` redirects to `/admin/login`; create credentials with `zypher createsuperuser`, which prompts for username, email, password, and password confirmation. Scaffolded admin login includes password recovery through `/admin/forgot-password` and `/admin/reset-password`. API variants return JSON from app routes and do not include project HTML templates.
`zypher run` infers the Zypher source root from the CLI binary and accepts `--port`; if omitted, scaffolded apps default to `8080`.

Serve generated documentation from the CLI:

```sh
zypher doc --port 8080
zypher doc-user examples/books-api --port 8081
```

`doc` serves the Zypher library docs; `doc-user` builds and serves docs for the selected user project.

### API Example

See `examples/books-api/` for an MVC-style JSON API with an admin dashboard for the `Book` model.

```sh
cd examples/books-api
zypher run .
```

The example listens on `127.0.0.1:8080` by default. Pass `--port` to choose another port:

```sh
zypher run . --port 8091
```

It exposes:

- `GET /api/books`
- `POST /api/books`
- `GET /api/books/:id`
- `POST /api/books/:id`
- `POST /api/books/:id/delete`

Create admin credentials for the example with:

```sh
zypher createsuperuser --db books_api.db
```

For noninteractive setup, pass all account fields:

```sh
zypher createsuperuser --username admin --email admin@example.com --password Passw0rd --db books_api.db
```

### Manual App

1. **Add zypher as a dependency** in your `build.zig.zon`
2. **Create a handler** — any function matching `*const fn (*Request, *Response) void`
3. **Register routes** at comptime
4. **Start the server**

### Minimal Example

```zig
const std = @import("std");
const zypher = @import("zypher");
const Route = zypher.router.Route;
const Router = zypher.router.Router;

fn index(req: *zypher.core.Request, res: *zypher.core.Response) void {
    _ = req;
    res.text("Hello from zypher") catch {};
}

fn notFound(req: *zypher.core.Request, res: *zypher.core.Response) void {
    _ = req;
    _ = res.status(404);
    res.text("Not Found") catch {};
}

pub fn main(init: std.process.Init) !void {
    const routes = [_]Route{
        Route.init(.get, "/", index),
    };
    var router = Router.initFromSlice(&routes, notFound);

    var app = zypher.core.App.init(init.gpa, .{ .port = 8080 });
    defer app.deinit();
    app.routerHandler(router.dispatch);

    try app.listenAndServe(init.io);
}
```

### With Middleware

```zig
const Chain = zypher.middleware.Chain;
const DemoRL = zypher.middleware.rate_limit.middlewareWith(
    .{ .max_requests = 100, .window_seconds = 60 },
);

fn mwHandler(req: *zypher.core.Request, res: *zypher.core.Response) void {
    const MwChain = Chain(.{
        zypher.middleware.logger.middleware,
        DemoRL.handle,
    });
    MwChain.run(req, res, router.dispatch);
}

app.middlewareHandler(mwHandler);
```

### Full Demo

See `examples/demo/` for a complete application with:
- ORM models (Post, Comment) backed by SQLite
- Template rendering with `{% extends %}`, `{% block %}`, `{{ variable|filter }}`
- Authentication (register, login, logout) with session management
- CSRF protection on all mutating requests
- Auto-generated admin panel for registered models
- Rate limiting and request logging middleware

---

## Project Structure

```
zypher/
├── src/
│   ├── core/          # Request / Response primitives
│   ├── router/        # Compile-time router
│   ├── middleware/    # Middleware system
│   ├── view/          # Controllers and helpers
│   ├── template/      # Template engine
│   ├── orm/           # ORM and migrations
│   ├── forms/         # Forms and validation
│   ├── auth/          # Authentication and sessions
│   ├── admin/         # Admin panel
│   └── cli/           # CLI tooling
├── examples/
├── templates/        # CLI scaffold templates
├── docs/
└── build.zig
```

---

## Status

**Early development (v0.x)**

zypher is currently under active development and evolving rapidly. APIs may change.

That said, the project is designed to be:
- Readable
- Well-documented
- Useful as a learning reference even before v1.0

---

##  Documentation

- Architecture & design decisions: see `docs/`
- Full project specification: see `zypher_PROJECT_SPEC.md`
- Examples: see `examples/`

---

##  Contributing

Contributions are welcome, especially:
- Clear bug reports
- Design discussions
- Documentation improvements

Before contributing, please read the project specification to understand the guiding principles.

---

##  Final Note

zypher is built with the belief that **frameworks should teach, not obscure**.

If you enjoy understanding systems from the ground up, you’ll feel at home here.

## License

Licensed under the Apache License, Version 2.0.  
See the [LICENSE](LICENSE) file for details.
