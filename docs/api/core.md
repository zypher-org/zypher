# Core API

## App
The main application struct. Manages the HTTP server lifecycle.

- `init(gpa, config) App` — Create a new app
- `deinit()` — Free all resources
- `handler(fn_ptr)` — Register a plain request handler
- `routerHandler(fn_ptr)` — Register a router dispatch handler
- `middlewareHandler(fn_ptr)` — Register a middleware pipeline handler
- `database(db)` — Attach an ORM database connection
- `buildRequestFromHead(head_buffer)` — Parse an HTTP request head
- `handleRequest(req, res)` — Dispatch through middleware, router, or handler
- `listenAndServe(io)` — Start serving requests
- `shutdown(io)` — Gracefully stop the server

## Request
Represents an incoming HTTP request.

- `method` — HTTP method (`Method` enum)
- `path` — Request path (`[]const u8`)
- `query` — Query string parameters (`StringHashMap`)
- `headers` — HTTP headers (`StringHashMap`)
- `body` — Raw body (`[]const u8`)
- `files` — Multipart uploaded files (`StringHashMap(Request.FileUpload)`) when `files_owned` is true
- `params` — Route-extracted URL parameters (`RouteParams`)
- `user` — Optional authenticated user (`?*anyopaque`)
- `header(name)` — Case-insensitive header lookup
- `queryParam(name)` — Query parameter lookup
- `formValue(name)` — Form value lookup
- `file(name)` — Multipart uploaded file lookup by field name
- `cookie(name)` — Cookie lookup
- `parseQueryString(gpa, raw)` — Parse URL query strings
- `parseFormUrlEncoded(gpa, body)` — Parse `application/x-www-form-urlencoded` bodies
- `parseMultipartFormData(gpa, content_type, body)` — Parse `multipart/form-data` into text fields and uploaded files
- `parseCookies(gpa, cookie_header)` — Parse cookie headers
- `validateBodySize(body_len, max)` — Enforce request body size limits

### FileUpload
- `filename` — Client-provided filename
- `content_type` — Part content type, or empty string when omitted
- `data` — Owned uploaded bytes

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
