# zypher — GitHub Project Specification

> **A batteries-included web framework, built the Zig way.**

---

## 1. Project Overview

**zypher** is a Django-inspired, batteries-included web framework written in **Zig**. Its purpose is not just to enable web development in Zig, but to **demonstrate how a modern web framework can be built from first principles using explicit, compile-time–driven abstractions**.

zypher prioritizes:
- Explicitness over magic
- Compile-time correctness
- Secure-by-default design
- Minimal runtime overhead
- Clear, readable APIs

This project is both a **production-capable framework** and a **learning reference** for systems-level web development.

---

## 2. Non‑Goals (Important)

zypher explicitly does **not** aim to:
- Compete feature-for-feature with Django
- Support every database backend
- Implement HTTP/2 or HTTP/3 initially
- Provide async-first APIs in v1
- Hide complexity through runtime reflection

These constraints keep the project focused and maintainable.

---

## 3. Target Audience

- Zig developers
- Systems programmers
- Developers interested in framework internals
- Learners who want to understand how Django-like systems work

---

## 4. Core Design Principles

1. **Explicit is better than implicit**
2. **Compile-time > runtime** wherever possible
3. **Security by default**
4. **Minimal allocations**
5. **One obvious way to do things**

---

## 5. High-Level Architecture

```
Browser
  ↓
HTTP Server
  ↓
Request Parser
  ↓
Router (compile-time routes)
  ↓
Middleware Pipeline
  ↓
View / Controller
  ↓
Template / JSON / Redirect
  ↓
Response
```

---

## 6. Repository Structure

```
zypher/
├── src/
│   ├── http/          # HTTP server integration
│   ├── core/          # Request / Response primitives
│   ├── router/        # Compile-time router
│   ├── middleware/    # Middleware system
│   ├── view/          # Controllers and helpers
│   ├── template/      # Template engine
│   ├── orm/           # ORM and migrations
│   ├── forms/         # Forms and validation
│   ├── auth/          # Authentication and sessions
│   ├── admin/         # Admin panel
│   └── cli/           # Command-line tooling
├── examples/
├── tests/
├── docs/
├── build.zig
└── README.md
```

---

## 7. Module Specifications

### 7.1 HTTP Layer (`src/http/`)

**Responsibilities**:
- Bind TCP listener
- Integrate `std.http.Server`
- Manage connection lifecycle

**Constraints**:
- HTTP/1.1 only
- No custom protocol parsing

---

### 7.2 Core Request / Response (`src/core/`)

#### Request
```zig
pub const Request = struct {
    method: Method,
    path: []const u8,
    headers: HeaderMap,
    query: QueryMap,
    body: []const u8,
};
```

#### Response
```zig
pub const Response = struct {
    status: u16,
    headers: HeaderMap,
    body: []const u8,
};
```

**Goals**:
- Zero raw HTTP usage in user code
- Helper methods for common responses

---

### 7.3 Router (`src/router/`)

**Features**:
- Compile-time route registration
- Typed URL parameters
- Deterministic matching order

**Example API**:
```zig
Router.route(.get, "/users/:id", userView);
const id = try req.params.getAs(u64, "id");
```

Invalid route definitions **must fail at compile time**.

---

### 7.4 Middleware (`src/middleware/`)

**Middleware Signature**:
```zig
fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void
```

**Use Cases**:
- Logging
- Authentication
- CSRF protection
- Panic recovery
- Static file serving
- Gzip compression

---

### 7.5 Views & Controllers (`src/view/`)

Controllers contain business logic only.

**Example**:
```zig
pub fn dashboard(req: *Request, res: *Response) !void {
    try res.render("dashboard.html", .{ .user = req.user });
}
```

---

### 7.6 Template Engine (`src/template/`)

**Supported Syntax (v1)**:
- `{{ variable }}`
- `{% if %}`
- `{% for %}`

**Rules**:
- Auto-escape HTML by default
- Templates parsed once, cached

---

### 7.7 ORM (`src/orm/`)

**Scope**:
- SQLite only (v1)
- Struct-based models
- Compile-time SQL generation

**Example**:
```zig
const User = orm.Model("users", struct {
    id: i32,
    username: []const u8,
    email: []const u8,
});
```

---

### 7.8 Migrations (`src/orm/migrations`)

- Versioned schema changes
- Forward-only migrations
- CLI-driven execution

---

### 7.9 Forms & Validation (`src/forms/`)

- Struct-based form definitions
- Field-level validation rules
- Automatic error aggregation
- CSRF protection

---

### 7.10 Authentication & Sessions (`src/auth/`)

**Features**:
- Signed cookie sessions
- Password hashing (PBKDF2-HMAC-SHA256)
- Login / logout
- Permissions system

---

### 7.11 Admin Panel (`src/admin/`)

**Features**:
- Auto-generated CRUD UI
- Model-based configuration
- Permission-aware access

---

### 7.12 CLI (`src/cli/`)

The CLI is the user-facing entrypoint for creating projects, running apps, administering local state, and serving documentation. Build it once from the repository root with `zig build`, then run `zypher` from `zig-out/bin` or your `PATH`.

**Commands**:
```bash
zypher new <path> [--template single-file|clean-arch|mvc|mvp] [--api] [--template-dir <dir>]
zypher templates [--template-dir <dir>]
zypher run [path] [--zypher-root <path>] [--port <port>] [-- <app args...>]
zypher doc [--zypher-root <path>] [--host <host>] [--port <port>]
zypher doc-user [path] [--host <host>] [--port <port>]
zypher migrate [--db <path>] [--dir <dir>]
zypher makemigrations [--schema <path>] [--state <path>] [--dir <dir>]
zypher createsuperuser [--username <name>] [--email <email>] [--password <password>] [--db <path>]
```

Scaffold templates live in the repository root `templates/` directory. Third-party templates can be used by pointing `--template-dir` at another directory. Built-in styles have paired template and API variants, such as `mvc` and `mvc-api`; `--api` selects the API sibling. Built-in templates generate a runnable `build.zig`, a sample managed ORM model, and an admin dashboard protected by `/admin/login`. `zypher createsuperuser` defaults to an interactive prompt for username, email, hidden password, and hidden password confirmation; noninteractive callers must pass username, email, and password together. Scaffolded admin login also includes `/admin/forgot-password` and `/admin/reset-password` for 6-digit password recovery codes. Users should start scaffolded apps through `zypher run`, which infers the Zypher source root, delegates to the generated build script, and forwards runtime options such as `--port`.

`zypher doc` builds and serves Zypher library documentation. `zypher doc-user` builds and serves documentation for a user project by running `zig build doc` in that project.

---

## 8. Development Rules

1. All public APIs must be documented
2. Prefer compile-time errors
3. Avoid global state
4. Write tests per module
5. Keep dependencies minimal

---

## 9. Versioning Strategy

- `v0.x`: Experimental
- `v1.0`: Stable core framework

---

## 10. Success Criteria

zypher is considered successful if:
- A complete CRUD app can be built
- The framework is readable end-to-end
- Developers can learn web internals by reading the source

---

## 11. License

Apache License, Version 2.0.
