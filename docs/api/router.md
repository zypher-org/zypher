# Router API

## Route
A single route definition.

- `init(method, pattern, handler) Route` — Create a route
- `validatePattern(pattern)` — Validate a path pattern at comptime
- `matchPath(pattern, actual, params)` — Match a path against a pattern, extracting params

### Pattern Syntax
- `/users/:id` — Named parameter
- `/users/:id[u64]` — Typed parameter (validates as u64)
- `/static/*` — Wildcard (matches remaining path)

## RouteParams
Zero-allocation URL parameter storage.

- `max_params = 16` — Maximum number of params
- `init(gpa) RouteParams` — Create empty params
- `deinit()` — Free resources
- `get(name)` — Get param value by name
- `getAs(T, name)` — Get param parsed as type T

## Router
Comptime route table with runtime dispatch.

- `route(method, pattern, handler) Route` — Create a route entry
- `group(prefix, routes)` — Group routes under a prefix
- `init(routes, notFoundHandler) Router` — Initialize from tuple
- `initFromSlice(routes, notFoundHandler) Router` — Initialize from slice
- `dispatch(req, res)` — Dispatch to matching handler

### Route Groups
```zig
const routes = .{
    Router.group("/api", .{
        Router.route(.get, "/users", listHandler),
        Router.route(.post, "/users", createHandler),
    }),
};
// Creates: /api/users for GET and POST
```
