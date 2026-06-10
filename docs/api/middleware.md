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
- `generateToken()` — Generate a CSRF token
- `validateToken(token)` — Validate a token
- `formField()` — Get HTML hidden input with token

## Rate Limit
Request rate limiting middleware.

- `middleware(req, res, next)` — Apply rate limits

## Static
Static file serving middleware.

- `middleware(req, res, next)` — Serve static files with defaults
- `middlewareWith(config)` — Custom configuration (root_dir, prefix, serve_index)

### Features
- MIME type detection, path traversal protection, ETag/304 support

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
Panic/error recovery middleware.

- `middleware(req, res, next)` — Catch errors and return 500
