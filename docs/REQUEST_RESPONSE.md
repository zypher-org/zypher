# zypher — Request & Response API

> **Current Status**
>
> This document describes the current pre-1.0 `Request` and `Response` API.
> It is the intended v1 shape, but the repository has not shipped a frozen v1
> contract yet. Breaking changes should be documented and covered by tests.

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
- Request header lookup is case-insensitive.
- Response headers own inserted names and values until `Response.deinit()`.
- Header values are immutable slices after insertion.

---

## 3. Request API

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

    /// Whether body was allocated and must be freed in deinit
    body_owned: bool = false,

    /// Whether query/form entries were allocated by decodeUrlEncoded
    query_owned: bool = false,

    /// Allocator scoped to this request
    allocator: std.mem.Allocator,

    /// Optional authenticated user (set by auth middleware)
    user: ?*anyopaque = null,

    // ───────────── Helpers ─────────────

    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {}

    pub fn queryParam(self: *const Request, name: []const u8) ?[]const u8 {}

    pub fn formValue(self: *const Request, name: []const u8) ?[]const u8 {}

    pub fn cookie(self: *const Request, name: []const u8) ?[]const u8 {}

    pub fn json(self: *const Request, comptime T: type) !T {}
};
```

### 3.1 Request Invariants

- `Request` is **read-only** to user code
- Body parsing is lazy
- All allocations use `request.allocator`
- Authentication is injected via middleware

---

## 4. Response API

```zig
pub const Response = struct {
    status_code: u16 = 200,
    reason_phrase: ?[]const u8 = "OK",
    headers: HeaderMap,
    set_cookie_headers: std.ArrayList([]const u8),
    body: ?[]const u8 = null,
    use_chunked: bool = false,

    allocator: std.mem.Allocator,

    // ───────────── Mutators ─────────────

    pub fn status(self: *Response, code: u16) *Response {}

    pub fn header(self: *Response, name: []const u8, value: []const u8) *Response {}

    pub fn addSetCookie(self: *Response, value: []const u8) *Response {}

    pub fn setCookie(self: *Response, cookie: Cookie) *Response {}

    pub fn deleteCookie(self: *Response, name: []const u8) *Response {}

    // ───────────── Writers ─────────────

    pub fn text(self: *Response, content: []const u8) !void {}

    pub fn html(self: *Response, content: []const u8) !void {}

    pub fn json(self: *Response, value: anytype) !void {}

    pub fn redirect(self: *Response, location: []const u8, code: u16) !void {}
};
```

---

## 5. Response Rules

- Headers must be written before body
- `text()` automatically sets `Content-Type: text/plain; charset=utf-8`
- `html()` automatically sets `Content-Type: text/html; charset=utf-8`
- `json()` automatically sets `Content-Type: application/json`
- `json()` accepts `anytype`; byte strings are treated as already serialized JSON, while typed values are serialized with `std.json`
- `redirect()` clears the body, sets `Location`, and uses the caller-provided redirect status
- `Set-Cookie` is stored separately from the singleton header map so multiple cookies serialize as multiple `Set-Cookie` lines
- `send()` always emits `Content-Length`, including `Content-Length: 0` for empty responses

---

## 6. Middleware Contract

Middleware interacts with Request / Response **only through this API**.

```zig
pub fn Middleware(
    req: *Request,
    res: *Response,
    next: *const fn (*Request, *Response) void,
) void;
```

Rules:
- Middleware may mutate Response
- Middleware must not replace Request
- Middleware may call `next(req, res)` and then post-process the response, or short-circuit by writing a response and returning

---

## 7. View / Controller Contract

```zig
pub fn View(req: *Request, res: *Response) !void;
```

Rules:
- Views never return data, only mutate Response
- Errors propagate to the framework

---

## 8. Compatibility Guardrails

Avoid these changes unless they are part of an explicit versioned API update:

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

## 10. Stability Direction

The project is still pre-1.0. Once a v1 release is declared, this document
should be tightened into a compatibility contract and tied to conformance tests.

---

## 11. Final Note

Everything else in zypher builds on this layer.

If this layer is correct, the framework remains correct.
