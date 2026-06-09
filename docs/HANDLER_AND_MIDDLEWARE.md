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
pub const HandlerFn = fn (req: *Request, res: *Response) void;
```

### Rules
- Handlers write into the provided `Response`
- Recoverable write errors are handled at the call site
- No global state allowed

### Example

```zig
fn hello(req: *Request, res: *Response) void {
    _ = req;
    res.text("Hello, zypher") catch {};
}
```

---

## 4. Middleware API (Frozen)

### Definition

```zig
pub const NextFn = *const fn (*Request, *Response) void;

pub const MiddlewareFn = fn (
    req: *Request,
    res: *Response,
    next: NextFn,
) void;
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

1. Middleware **may call `next(req, res)` once** to continue the chain
2. Middleware **may short‑circuit** (return Response early)
3. Middleware **must not mutate Request**
4. Middleware **may modify Response before returning**
5. Middleware that post-processes a response must call `next(req, res)` before rewriting headers or body

---

## 6. Middleware Examples

### Logging

```zig
fn logger(req: *Request, res: *Response, next: NextFn) void {
    std.log.info("{s} {s}", .{ @tagName(req.method), req.path });
    next(req, res);
    std.log.info("-> {}", .{res.status_code});
}
```

### Auth Guard

```zig
fn requireAuth(req: *Request, res: *Response, next: NextFn) void {
    if (req.header("Authorization") == null) {
        _ = res.status(401);
        res.json(.{ .error = "Unauthorized" }) catch {};
        return;
    }
    next(req, res);
}
```

### Static Files

`middleware.static.middlewareWith(.{ .root_dir = "./public", .prefix = "/static" })`
serves existing files from the configured root, rejects `..` traversal, sets MIME
type from the extension, and passes missing files through to the next handler.

### Compression

`middleware.compress.middleware` checks `Accept-Encoding` for `gzip`, calls the
next handler first, then gzip-compresses a non-empty response body. It sets
`Content-Encoding: gzip` and `Vary: Accept-Encoding`; responses without gzip
support pass through unchanged.

---

## 7. Error Handling Strategy

- Handlers generally write into `Response`
- Middleware decides:
  - recover
  - transform
  - propagate

### Example Recovery Middleware

```zig
fn recover(req: *Request, res: *Response, next: NextFn) void {
    next(req, res);
    if (res.status_code >= 500 and res.body == null) {
        res.text("Internal Server Error") catch {};
    }
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
- Thread-local state is reserved for closure-free framework internals such as session store wiring and chain dispatch

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
