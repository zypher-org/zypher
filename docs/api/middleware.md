# Middleware API

## Chain
Comptime middleware pipeline.

- `Chain(middlewares)` — Create a chain type
- `Chain.run(req, res, handler)` — Execute the middleware chain

## Logger
Request logging middleware.

- `middleware(req, res, next)` — Log all requests

## CORS
Cross-Origin Resource Sharing middleware.

- `middleware(req, res, next)` — Handle CORS headers
- `middlewareWith(config)` — Custom CORS configuration

## CSRF
Cross-Site Request Forgery protection.

- `middleware(req, res, next)` — Validate CSRF tokens
- `ensureToken(req)` — Return the request token, creating and storing a random token in the attached session when present
- `validateTokenForRequest(req, token)` — Validate against the attached session token when present
- `formFieldForRequest(gpa, req)` — Return an owned hidden input using the request/session token
- `generateToken()` / `validateToken(token)` / `formField()` — No-session fallback API for apps that do not install session middleware

## Rate Limit
Request rate limiting middleware.

- `middleware(req, res, next)` — Apply rate limits

## Static
Static file serving middleware.

- `middleware(req, res, next)` — Serve static files with defaults
- `middlewareWith(config)` — Custom configuration (root_dir, prefix, serve_index)

### Features
- MIME type detection, path traversal protection, ETag/304 support, `Last-Modified`, and `If-Modified-Since`

## Compress
Response compression middleware.

- `middleware(req, res, next)` — Compress responses

## Session
Session management middleware.

- `middleware(req, res, next)` — Attach session to request

## Security Headers
Security header injection middleware.

- `middleware(req, res, next)` — Add security headers

## Recovery
Recovery middleware placeholder.

- `middleware(req, res, next)` — Calls the next handler. It does not catch panics with the current Zig/runtime API.
- API decision: panic recovery is not exposed as in-process middleware because Zig panics are not recoverable through this function signature. Use process supervision for panic isolation.
