# zypher Framework – Handler & Middleware API (v1)

> **Status:**  Frozen (v1)
>
> This document defines the *core execution model* of zypher.
> Once frozen, all routing, HTTP adapters, async runtimes, and extensions must conform to this API.

---

## 1. Design Goals

1. **Explicit over implicit** – no magic globals
2. **Allocator-aware** – all memory ownership is visible
3. **Middleware-first** – cross‑cutting concerns are first‑class
4. **Sync-first, async-ready** – async can be layered later
5. **Composable** – handlers are plain functions

---

## 2. Core Types (Context)

```zig
pub const Context = struct {
    req: *const Request,
    allocator: std.mem.Allocator,
};
```

### Notes
- `Request` is immutable
- Context is **read-only** except allocator usage
- No response stored in context (prevents hidden side effects)

---

## 3. Handler API (Frozen)

### Definition

```zig
pub const HandlerFn = fn (ctx: *Context) anyerror!Response;
```

### Rules
- Handlers **must** return a `Response`
- Errors propagate upward (middleware decides how to handle them)
- No global state allowed

### Example

```zig
fn hello(ctx: *Context) !Response {
    return Response.text(ctx.allocator, "Hello, zypher");
}
```

---

## 4. Middleware API (Frozen)

### Definition

```zig
pub const NextFn = fn (ctx: *Context) anyerror!Response;

pub const MiddlewareFn = fn (
    ctx: *Context,
    next: NextFn,
) anyerror!Response;
```

### Execution Model

```text
Request
  ↓
Middleware 1
  ↓
Middleware 2
  ↓
Handler
  ↓
Middleware 2 (return)
  ↓
Middleware 1 (return)
  ↓
Response
```

---

## 5. Middleware Rules (Strict)

1. Middleware **must call `next(ctx)` exactly once**
2. Middleware **may short‑circuit** (return Response early)
3. Middleware **must not mutate Request**
4. Middleware **may modify Response before returning**

---

## 6. Middleware Examples

### Logging

```zig
fn logger(ctx: *Context, next: NextFn) !Response {
    std.log.info("{s} {s}", .{ ctx.req.method, ctx.req.path });
    const res = try next(ctx);
    std.log.info("→ {}", .{ res.status });
    return res;
}
```

### Auth Guard

```zig
fn requireAuth(ctx: *Context, next: NextFn) !Response {
    if (!ctx.req.headers.contains("Authorization")) {
        return Response.json(ctx.allocator, 401, "Unauthorized");
    }
    return try next(ctx);
}
```

---

## 7. Error Handling Strategy

- Handlers return errors
- Middleware decides:
  - recover
  - transform
  - propagate

### Example Recovery Middleware

```zig
fn recover(ctx: *Context, next: NextFn) Response {
    return next(ctx) catch |err| {
        return Response.text(ctx.allocator, "Internal Server Error");
    };
}
```

---

## 8. Composition Model

```zig
const app = App.init(allocator);

app.use(logger);
app.use(recover);

app.get("/", hello);
```

> `App` is **not frozen** yet — only the function contracts are.

---

## 9. Invariants (Non‑Negotiable)

- No middleware mutation of request
- No implicit response writing
- No hidden async runtime
- No thread-local storage

Violations require a **major version bump**.

---

## 10. Why This Works

- Mirrors Zig philosophy
- Predictable control flow
- Easy to test
- Easy to reason about
- Easy to port to async / WASM / embedded

---

## 11. Status

 Handler API frozen (v1)

 Middleware API frozen (v1)

 Safe to build router, server, and extensions

