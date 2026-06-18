# Core API

## Method
HTTP method enum with 7 variants: `get`, `post`, `put`, `patch`, `delete`, `options`, `head`.

## SameSite
Cookie `SameSite` attribute enum:
- `Strict` — only sent for same-site requests
- `Lax` — sent for top-level navigations from other sites (default)
- `None` — sent for all requests (requires `Secure` flag)

## Cookie
Configuration struct for `Set-Cookie` headers:
- `name: []const u8` — cookie name
- `value: []const u8 = ""` — cookie value
- `path: []const u8 = "/"` — cookie path
- `domain: ?[]const u8 = null` — cookie domain
- `max_age: ?u32 = null` — max age in seconds
- `secure: bool = false` — only send over HTTPS
- `http_only: bool = false` — not accessible to JavaScript
- `same_site: SameSite = .Lax` — SameSite policy

## Server
Low-level HTTP server. Binds to a host:port, accepts connections, parses HTTP, and dispatches to a handler.

### Server.Config
- `host: []const u8 = "127.0.0.1"` — bind address
- `port: u16 = 8080` — listen port
- `read_buffer_size: usize = 8192` — read buffer size
- `write_buffer_size: usize = 8192` — write buffer size
- `max_body_size: usize = 10_485_760` — max request body (10 MiB)
- `max_inline_body_size: usize = 1_048_576` — max body buffered before streaming (1 MiB); bodies larger than this are read via `Request.body_stream`
- `max_requests: ?usize = null` — optional request limit (for tests)

### Constants & Types
- `HandlerFn = *const fn (*Request, *Response) void` — handler function signature
- `ParsedTarget` — result of parsing a request target:
  - `path: []const u8` — path portion
  - `query: std.StringHashMap([]const u8)` — parsed query parameters

### Methods
- `Server.init(config: Config) Server` — create a new server with the given config
- `server.listenAddress(host, port) IpAddress` — parse host + port into an address
- `server.parseRequestTarget(gpa, target) ParsedTarget` — parse a request target into path and query
- `server.buildRequest(gpa, head_buffer, max_body_size) Request` — build a `Request` from raw HTTP head bytes; parses method, target, headers, validates content-length
- `server.listenAndServe(io, gpa, handler)` — start listening and dispatching; accepts io and allocator; blocks until shutdown or `max_requests` reached
- `server.shutdown(io)` — set shutdown flag and close listener

### Request Flow
1. `listenAndServe` binds the address and accepts connections in a loop
2. Each connection is parsed via `std.http.Server.receiveHead()`
3. `buildRequest` parses the head buffer into a `Request` struct
4. If the method expects a body, it reads it, then auto-parses `application/x-www-form-urlencoded` and `multipart/form-data`
5. The handler is called with `&req, &res`
6. `Response.send()` serializes the response back to the client

## App
High-level application struct that wraps Server, handlers, router, middleware, and database.

### Fields
- `server: Server` — the underlying HTTP server
- `allocator: std.mem.Allocator` — memory allocator
- `handler_fn: ?Server.HandlerFn = null` — terminal request handler
- `router_handler: ?Server.HandlerFn = null` — router dispatch handler (takes priority over `handler_fn`)
- `middleware_handler: ?Server.HandlerFn = null` — middleware pipeline handler (takes priority over all)
- `db: ?*sqlite.Db = null` — optional ORM database connection

### Methods
- `App.init(gpa, config) App` — create a new app with allocator and server config
- `app.deinit()` — free resources (closes database if attached)
- `app.handler(fn_ptr)` — register a plain request handler (`*const fn (*Request, *Response) void`)
- `app.routerHandler(fn_ptr)` — register a router dispatch handler (takes priority over plain handler)
- `app.database(db)` — attach an ORM database connection
- `app.middlewareHandler(fn_ptr)` — register a middleware pipeline handler (takes priority over router and handler)
- `app.buildRequestFromHead(head_buffer) Request` — parse an HTTP request head into a `Request`
- `app.handleRequest(req, res)` — dispatch through middleware → router → handler → default 404
- `app.listenAndServe(io)` — start the server; blocks until shutdown. Warns if no handler is registered.
- `app.shutdown(io)` — gracefully stop the server

### Handler Priority
1. `middleware_handler` — if set, called first; responsible for calling the terminal handler
2. `router_handler` — called if no middleware handler
3. `handler_fn` — called if no router handler
4. Default 404 — returned if nothing is registered

## Request
Represents an incoming HTTP request.

### Fields
- `method: Method` — HTTP method enum
- `path: []const u8` — raw request path (e.g. `"/users/42"`)
- `query: std.StringHashMap([]const u8)` — URL query string parameters
- `headers: std.StringHashMap([]const u8)` — HTTP headers
- `body: []const u8` — raw request body
- `body_owned: bool = false` — whether body was allocated (freed in deinit)
- `query_owned: bool = false` — whether query entries were allocated by `decodeUrlEncoded`
- `files: std.StringHashMap(FileUpload)` — multipart uploaded files keyed by field name
- `files_owned: bool = false` — whether files has been initialized
- `params: RouteParams` — route-extracted URL parameters (populated by Router.dispatch)
- `allocator: std.mem.Allocator` — allocator scoped to this request
- `user: ?*anyopaque = null` — optional authenticated user (set by session/auth middleware)
- `body_stream: ?BodyStream = null` — streaming body reader for bodies exceeding `max_inline_body_size`

### FileUpload
- `filename: []const u8` — client-provided filename
- `content_type: []const u8` — part content type (empty string when omitted)
- `data: []const u8` — owned uploaded bytes
- `fileUpload.deinit(gpa)` — free all owned memory

### MultipartForm
- `fields: std.StringHashMap([]const u8)` — text form fields
- `files: std.StringHashMap(FileUpload)` — uploaded files
- `allocator: std.mem.Allocator` — allocator
- `multipart.deinit()` — free all resources

### Instance Methods
- `req.header(name) ?[]const u8` — case-insensitive header lookup
- `req.queryParam(name) ?[]const u8` — query parameter lookup
- `req.formValue(name) ?[]const u8` — form value lookup (same storage as query for URL-encoded bodies)
- `req.file(name) ?FileUpload` — multipart uploaded file lookup by field name
- `req.range() ?Range` — parse HTTP Range header
- `req.cookie(name) ?[]const u8` — cookie lookup (parses `Cookie` header)
- `req.deinit()` — free all owned memory (headers, body, query, files)

### Static Methods
- `Request.parsePath(target) []const u8` — extract path from request target (before `?`)
- `Request.parseQueryString(gpa, raw) StringHashMap` — parse URL query string into a map; decoded values are owned
- `Request.deinitQueryString(map, gpa)` — free all memory from `parseQueryString`
- `Request.parseFormUrlEncoded(gpa, body) StringHashMap` — parse `application/x-www-form-urlencoded` body
- `Request.parseMultipartFormData(gpa, content_type, body) MultipartForm` — parse `multipart/form-data` into text fields and files
- `Request.deinitFiles(files, gpa)` — free all memory from a file upload map
- `Request.parseCookies(gpa, cookie_header) StringHashMap` — parse cookie header into a map
- `Request.getHeaderCI(headers, name) ?[]const u8` — case-insensitive header lookup from any header map
- `Request.validateBodySize(body_len, max) !void` — validate body size against a maximum; returns `error.BodyTooLarge` if exceeded

### Auto-parsing
When the server receives a request with a body, it auto-detects the content type:
- `application/x-www-form-urlencoded` — parsed into `req.query` (and thus accessible via `formValue`)
- `multipart/form-data` — text fields go into `req.query`, files go into `req.files`

## Response
Represents an outgoing HTTP response.

### Fields
- `status_code: u16 = 200` — HTTP status code
- `reason_phrase: ?[]const u8 = "OK"` — reason phrase (auto-set for known codes)
- `headers: std.StringHashMap([]const u8)` — response headers (owned)
- `set_cookie_headers: std.ArrayList([]const u8)` — raw `Set-Cookie` header values
- `body: ?[]const u8 = null` — response body (owned)
- `use_chunked: bool = false` — use `Transfer-Encoding: chunked`
- `file_body: ?FileBody = null` — streaming file descriptor (fd + size) for large payloads
- `allocator: std.mem.Allocator` — memory allocator

### Types
- `SameSite` enum: `Strict`, `Lax`, `None`
- `Cookie` struct: name, value, path, domain, max_age, secure, http_only, same_site
- `FileBody` struct: `fd: std.posix.fd_t`, `size: usize` — file descriptor for streaming file responses

### Lifecycle
- `Response.init(gpa) Response` — create a new response
- `res.deinit()` — free all owned memory (body, headers, cookie headers)

### Chaining Mutators
All mutators return `*Response` for chaining unless they return an error union.

- `res.status(code) *Response` — set HTTP status code; auto-sets reason phrase for known codes (200, 201, 204, 301, 302, 303, 307, 308, 400, 401, 403, 404, 405, 413, 422, 429, 500, 502, 503)
- `res.header(name, value) *Response` — set a response header; rejects CR/LF characters to prevent header injection; allocates owned copies of name and value
- `res.addSetCookie(value) *Response` — add a raw `Set-Cookie` header value; multiple `Set-Cookie` headers are preserved

### Body Writers
- `res.text(content) !void` — set plain text body (`Content-Type: text/plain; charset=utf-8`)
- `res.html(content) !void` — set HTML body (`Content-Type: text/html; charset=utf-8`)
- `res.json(content: anytype) !void` — set JSON body; byte slices are treated as pre-serialized JSON; other types are serialized via `std.json.Stringify` (`Content-Type: application/json`)
- `res.stream(content) !void` — set chunked streaming response (`Transfer-Encoding: chunked`, `Content-Type: text/plain; charset=utf-8`)
- `res.redirect(url, code) !void` — set redirect with `Location` header and status code

### Cookie Helpers
- `res.setCookie(cookie: Cookie) *Response` — add a `Set-Cookie` header from a `Cookie` struct; builds the full cookie string with `Path`, `Domain`, `Max-Age`, `Secure`, `HttpOnly`, `SameSite` attributes
- `res.deleteCookie(name) *Response` — delete a cookie by setting `Max-Age=0`

### File Body
- `res.setFileBody(fd, size) !void` — set a file descriptor as the response body for streaming; bypasses buffering the entire payload in memory

### Serialization
- `res.send(gpa, out: *ArrayList(u8)) !void` — serialize the full HTTP response (status line, headers, Set-Cookie headers, body) into the provided ArrayList; if `file_body` is set, sends headers only (the caller is responsible for sending file contents)

### Known Status Codes
200 OK, 201 Created, 204 No Content, 206 Partial Content, 301 Moved Permanently, 302 Found, 303 See Other, 304 Not Modified, 307 Temporary Redirect, 308 Permanent Redirect, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 405 Method Not Allowed, 413 Payload Too Large, 416 Range Not Satisfiable, 422 Unprocessable Entity, 429 Too Many Requests, 500 Internal Server Error, 502 Bad Gateway, 503 Service Unavailable

## Full Example

```zig
const std = @import("std");
const zypher = @import("zypher");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var app = zypher.core.App.init(gpa.allocator(), .{ .port = 8080 });

    app.handler(struct {
        fn handle(req: *zypher.core.Request, res: *zypher.core.Response) void {
            _ = req;
            res.text("Hello, World!") catch {};
        }
    }.handle);

    try app.listenAndServe(std.Io.default(gpa.allocator()));
}
```
