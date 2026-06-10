# Core API

## App
The main application struct. Manages the HTTP server lifecycle.

- `init(gpa, config) App` — Create a new app
- `deinit()` — Free all resources
- `get(handler)` — Register a GET handler
- `post(handler)` — Register a POST handler
- `listenAndServe(io)` — Start serving requests
- `shutdown(io)` — Gracefully stop the server

## Request
Represents an incoming HTTP request.

- `method` — HTTP method (`Method` enum)
- `path` — Request path (`[]const u8`)
- `query` — Query string parameters (`StringHashMap`)
- `headers` — HTTP headers (`StringHashMap`)
- `body` — Raw body (`[]const u8`)
- `params` — Route-extracted URL parameters (`RouteParams`)
- `user` — Optional authenticated user (`?*anyopaque`)
- `header(name)` — Case-insensitive header lookup
- `queryParam(name)` — Query parameter lookup
- `formValue(name)` — Form value lookup
- `cookie(name)` — Cookie lookup

## Response
Represents an outgoing HTTP response.

- `init(gpa) Response` — Create a new response
- `deinit()` — Free all owned memory
- `status(code)` — Set status code (chainable)
- `header(name, value)` — Set header (chainable)
- `text(content)` — Set plain text body
- `html(content)` — Set HTML body
- `json(content)` — Set JSON body
- `redirect(url, code)` — Redirect response
- `stream(content)` — Chunked streaming response
- `setCookie(cookie)` — Add Set-Cookie header
- `deleteCookie(name)` — Delete a cookie
- `send(gpa, out)` — Serialize response to bytes

## Method
HTTP method enum: `get`, `post`, `put`, `patch`, `delete`, `options`, `head`
