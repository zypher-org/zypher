# Middleware API

## Chain
Comptime middleware pipeline. Since Zig has no closures, the `next` callback is solved by generating the entire dispatch chain at comptime — each Chain type has its `run` method fully unrolled.

### Types
- `MiddlewareFn = *const fn (*Request, *Response, *const fn (*Request, *Response) void) void` — middleware function signature
- `HandlerFn = *const fn (*Request, *Response) void` — terminal handler function signature

### Chain type
```zig
const MyChain = comptime Chain(.{ mwLogger, mwCors });
```

- `Chain(middlewares)` — create a chain type; validates all items are functions at compile time
- `Chain.run(req, res, handler)` — execute the middleware chain, ending with `handler`

### Thread-local Terminal Handler
The terminal handler is passed through a `threadlocal` variable because Zig inner functions cannot capture outer parameters.

## Logger
Request logging middleware using `std.log.scoped(.http)`.

### middleware(req, res, next)
Logs: HTTP method, path, response status code, and elapsed time in microseconds. Uses `CLOCK_MONOTONIC` for timing.

## CORS
Cross-Origin Resource Sharing middleware.

### Config
- `allowed_origins: ?[]const []const u8 = null` — allowed origins; `null` allows all (reflects request `Origin`), empty slice blocks all
- `allowed_methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS"` — methods for preflight
- `allowed_headers: []const u8 = "Content-Type, Authorization, X-CSRF-Token"` — headers for preflight
- `max_age: []const u8 = "86400"` — preflight cache duration
- `allow_credentials: bool = false` — allow credentials (cookies, auth headers)

### middleware(req, res, next)
Default CORS middleware — allows all origins.

### middlewareWith(config)(req, res, next)
Create a CORS middleware with custom `Config`. Returns a comptime-generated function pointer.

### Behavior
- Requests without `Origin` header pass through (not a CORS request)
- `OPTIONS` preflight requests return 204 with CORS headers
- Normal CORS requests get `Access-Control-Allow-Origin` header and pass through
- Blocked origins get 403

## CSRF
Cross-Site Request Forgery protection middleware. Stores a 256-bit random token in the session.

### Behavior
- Safe methods (GET, HEAD, OPTIONS): pass through, token set in `X-CSRF-Token` response header
- Unsafe methods (POST, PUT, DELETE, PATCH): validate `X-CSRF-Token` header or `_csrf` form value against session

### Functions
- `middleware(req, res, next)` — CSRF middleware function
- `ensureToken(req) ![]const u8` — return the CSRF token from the session, creating and storing a random one if absent; requires `req.user` to be a `*Session`
- `validateTokenForRequest(req, token) bool` — validate a token against the session token (constant-time comparison)
- `formFieldForRequest(gpa, req) ![]u8` — return an owned HTML hidden input `<input type="hidden" name="_csrf" value="...">` using the request session token
- `formField() []const u8` — no-session fallback (returns empty string)

## Rate Limit
Fixed window rate limiter per client IP.

### Config
- `max_requests: u32 = 100` — max requests per window
- `window_seconds: u32 = 60` — window duration

### RateLimiter
- `RateLimiter.init(allocator, config) RateLimiter` — create a new limiter
- `limiter.deinit()` — free internal state
- `limiter.allow(key) !bool` — check if a request from the given key is allowed

### middleware(req, res, next)
Default rate limit middleware (100 req/min). Uses `X-Forwarded-For` header or `"default"` as the key.

### middlewareWith(config)
Create a rate limit middleware type with custom configuration. Returns a struct type with:
- `handle(req, res, next)` — the middleware function
- `deinit()` — free internal state
- `middleware()` — get the function pointer for use in Chain

## Static
Static file serving middleware.

### Config
- `root_dir: []const u8 = "./public"` — root directory to serve files from
- `prefix: []const u8 = "/"` — URL prefix to strip
- `serve_index: bool = true` — whether to serve index.html for directory paths

### middleware(req, res, next)
Default static middleware (root: `./public`).

### middlewareWith(config)
Create a static middleware with custom config. Returns a comptime-generated function pointer.

### Features
- MIME type detection by extension (html, css, js, json, png, jpg, gif, svg, ico, webp, woff, woff2, ttf, txt, xml, pdf, zip)
- Path traversal protection (rejects `..` segments)
- ETag/304 support via `If-None-Match` (XxHash32 of content)
- `Last-Modified` / `If-Modified-Since` support (Linux only, uses `statx`)
- Passes through to next handler if file not found

## Compress
Response compression middleware (gzip).

### middleware(req, res, next)
Compresses response body with gzip if client sends `Accept-Encoding: gzip`. Skips encoding if:
- Client doesn't accept gzip
- Response already has a `Content-Encoding` header
- Response has no body or empty body

Sets `Content-Encoding: gzip` and `Vary: Accept-Encoding` headers.

## Session
Session management middleware. Loads/saves session on every request.

### Thread-local Configuration
- `setStore(store: *SessionStore)` — set the session store for the current thread
- `setCookieConfig(config: CookieConfig)` — set cookie attributes (HttpOnly, Secure, SameSite, Path, Max-Age)
- `resetCookieConfig()` — restore default secure cookie config

### middleware(req, res, next)
1. Reads `zypher_session` cookie
2. Loads session from store via cookie hex ID
3. Attaches session pointer to `req.user` (cast to `*anyopaque`)
4. If no valid session, creates a new one, sets cookie, and attaches it
5. Calls `next` (handler may mutate session data through the pointer)
6. Post-handler: session is already saved via the pointer's in-place modifications

## Security Headers
Security header injection middleware. Sets standard security-related HTTP headers on every response.

### Options
- `x_content_type_options: bool = true` — `X-Content-Type-Options: nosniff`
- `x_frame_options: bool = true` — `X-Frame-Options: DENY`
- `referrer_policy: bool = true` — `Referrer-Policy: strict-origin-when-cross-origin`
- `x_xss_protection: bool = true` — `X-XSS-Protection: 0`
- `content_security_policy: bool = false` — `Content-Security-Policy: default-src 'self'`
- `strict_transport_security: bool = false` — `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `custom_headers: []const []const u8 = &.{}` — custom header name/value pairs (flat array)

### Functions
- `configure(opts: Options) void` — configure security headers (thread-local)
- `middleware(req, res, next)` — add configured security headers

## Recovery
Recovery middleware placeholder. Zig panics are not recoverable through a middleware function signature; this middleware simply calls `next(req, res)`. Use process supervision for panic isolation.

### middleware(req, res, next)
Calls the next handler. Does not catch panics.
