# Zypher

> **A batteries-included web framework, built the Zig way.**

Zypher is a Django-inspired web framework written in **Zig**, designed for developers who want **clarity, control, and correctness** without sacrificing productivity.

It provides the full set of tools needed to build server-side web applications — routing, middleware, templates, ORM, authentication, and an admin panel — while staying true to Zig’s philosophy: **explicit over magic, compile-time over runtime, and simplicity over cleverness**.

---

## Why Zypher?

Most web frameworks fall into one of two camps:
- *Minimal* frameworks that leave everything to you
- *Magical* frameworks that hide too much

Zypher sits deliberately in the middle.

It gives you **batteries included**, but every abstraction is:
- Understandable
- Inspectable
- Replaceable

If you’ve ever wondered *“how does Django actually work under the hood?”*, Zypher is built to answer that — in code.

---

## Design Philosophy

- **Explicit is better than implicit**
- **Compile-time correctness beats runtime surprises**
- **Security by default**
- **Minimal allocations, predictable performance**
- **One obvious way to do things**

Zypher avoids runtime reflection and hidden global state. Instead, it uses Zig’s compile-time features to catch errors early and generate efficient code.

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

## What Zypher Is *Not*

Zypher does **not** try to:
- Replace Django feature-for-feature
- Support every database or protocol
- Hide complexity through runtime magic
- Be async-first (yet)

The goal is **correctness, clarity, and learning value**, not maximum buzzwords.

---

## Example

```zig
const Zypher = @import("Zypher");

pub fn index(req: *Zypher.Request, res: *Zypher.Response) !void {
    try res.text("Hello from Zypher 👋");
}

pub fn main() !void {
    var app = Zypher.App.init();

    app.router.get("/", index);

    try app.run(.{ .port = 8080 });
}
```

---

## Project Structure

```
Zypher/
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
├── docs/
└── build.zig
```

---

## Status

**Early development (v0.x)**

Zypher is currently under active development and evolving rapidly. APIs may change.

That said, the project is designed to be:
- Readable
- Well-documented
- Useful as a learning reference even before v1.0

---

##  Documentation

- Architecture & design decisions: see `docs/`
- Full project specification: see `ZYPHER_PROJECT_SPEC.md`
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

Zypher is built with the belief that **frameworks should teach, not obscure**.

If you enjoy understanding systems from the ground up, you’ll feel at home here.

## License

Licensed under the Apache License, Version 2.0.  
See the [LICENSE](LICENSE) file for details.
