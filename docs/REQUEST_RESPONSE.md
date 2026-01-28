# zypher — Request & Response API (FROZEN v1)

> ⚠️ **API FREEZE NOTICE**
>
> This document defines the **stable v1 API contract** for `Request` and `Response`.
> Any breaking change requires a major version bump or a formal RFC.
>
> All higher-level modules (router, middleware, views, templates, auth, ORM) MUST depend on this API exactly as defined.

---

## 1. Design Goals

The Request / Response layer must:

- Hide raw HTTP details from application code
- Be immutable where possible
- Avoid global state
- Minimize allocations
- Be explicit and predictable
- Support middleware and views cleanly

---

## 2. Core Types

### 2.1 HTTP Method

```zig
pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    HEAD,
};
```

---

### 2.2 Header Map

```zig
pub const HeaderMap = std.StringHashMap([]const u8);
```

Rules:
- Header keys are normalized to lowercase
- Header values are immutable slices

---

## 3. Request API (FROZEN)

```zig
pub const Request = struct {
    /// HTTP method
    method: Method,

    /// Raw request path (e.g. "/users/42")
    path: []const u8,

    /// Query string parameters
    query: std.StringHashMap([]const u8),

    /// HTTP headers
    headers: HeaderMap,

    /// Raw request body
    body: []const u8,

    /// Allocator scoped to this request
    allocator: std.mem.Allocator,

    /// Optional authenticated user (set by auth middleware)
    user: ?*anyopaque = null,

    // ───────────── Helpers ─────────────

    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {}

    pub fn queryParam(self: *const Request, name: []const u8) ?[]const u8 {}

    pub fn json(self: *const Request, comptime T: type) !T {}
};
```

### 3.1 Request Invariants

- `Request` is **read-only** to user code
- Body parsing is lazy
- All allocations use `request.allocator`
- Authentication is injected via middleware

---

## 4. Response API (FROZEN)

```zig
pub const Response = struct {
    status: u16 = 200,
    headers: HeaderMap,
    body: []const u8 = "",

    allocator: std.mem.Allocator,

    // ───────────── Mutators ─────────────

    pub fn setStatus(self: *Response, code: u16) void {}

    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {}

    // ───────────── Writers ─────────────

    pub fn text(self: *Response, content: []const u8) !void {}

    pub fn html(self: *Response, content: []const u8) !void {}

    pub fn json(self: *Response, value: anytype) !void {}

    pub fn redirect(self: *Response, location: []const u8) !void {}
};
```

---

## 5. Response Rules

- Headers must be written before body
- `json()` automatically sets `Content-Type: application/json`
- `html()` automatically sets `Content-Type: text/html`
- `redirect()` sets status to `302` by default

---

## 6. Middleware Contract

Middleware interacts with Request / Response **only through this API**.

```zig
pub fn Middleware(
    req: *Request,
    res: *Response,
    next: fn () anyerror!void,
) anyerror!void;
```

Rules:
- Middleware may mutate Response
- Middleware must not replace Request
- Middleware must call `next()` exactly once

---

## 7. View / Controller Contract

```zig
pub fn View(req: *Request, res: *Response) !void;
```

Rules:
- Views never return data, only mutate Response
- Errors propagate to the framework

---

## 8. Forbidden Changes (v1)

The following are **explicitly forbidden** in v1:

- Adding runtime reflection to Request / Response
- Exposing raw `std.http` types
- Implicit global context
- Implicit JSON/body parsing
- Hidden allocation behavior

---

## 9. Testing Requirements

Every method in Request / Response must have:
- Unit tests
- Allocation tests
- Error-path tests

CI must fail if these tests fail.

---

## 10. Stability Promise

This API is guaranteed stable for all `v1.x` releases.

Breaking changes require:
- RFC document
- Version bump to `v2.0`

---

## 11. Final Note

Everything else in zypher builds on this layer.

If this layer is correct, the framework remains correct.

