# Router API

## Route
A single route definition combining an HTTP method, a URL pattern, and a handler function.

### Route.init(method, pattern, handler) Route
Create a route entry.
- `method: Method` — HTTP method (`.get`, `.post`, `.put`, `.patch`, `.delete`, `.options`, `.head`)
- `pattern: []const u8` — URL pattern (e.g. `"/users/:id"`)
- `handler: *const fn (*Request, *Response) void` — request handler

### Route.validatePattern(pattern) !void
Validate a path pattern at comptime. Called automatically by `Router.init`. Returns an error for invalid patterns:
- `error.InvalidPattern` — empty pattern, not starting with `/`, multiple wildcards, wildcard not last, empty param names, duplicate params

### Route.matchPath(pattern, actual, params) bool
Match a concrete path against a pattern at runtime, extracting named parameters into the provided `RouteParams`. Returns `true` on match.

## RouteParams
Zero-allocation URL parameter storage (fixed-size array of 16 entries).

### Constants
- `max_params = 16` — maximum number of URL parameters

### Methods
- `RouteParams.init(gpa) RouteParams` — create empty params
- `params.deinit()` — free resources
- `params.get(name) ?[]const u8` — get param value by name
- `params.getAs(T, name) !T` — get param parsed as type `T` (e.g. `params.getAs(u64, "id")`); returns `error.MissingParam` if not found, or parse error if value is invalid

## Router
Comptime route table with runtime dispatch. Routes are defined at comptime; dispatch uses a linear scan with specificity scoring at runtime.

### Methods
- `Router.route(method, pattern, handler) Route` — create a route entry (comptime-friendly helper)
- `Router.group(prefix, routes) []const Route` — create a grouped set of routes with a common prefix
- `Router.init(routes, notFoundHandler) Router` — initialize router from a comptime tuple/array of routes; validates all patterns at compile time
- `Router.initFromSlice(routes, notFoundHandler) Router` — initialize router from a runtime slice of routes (no comptime validation)
- `router.dispatch(req, res)` — dispatch a request to the matching route handler

### Dispatch Algorithm
1. For each registered route, attempt pattern match via `Route.matchPath`
2. If path matches and method matches, score by specificity (static > named param > wildcard)
3. Pick the highest-scoring match and call its handler, populating `req.params`
4. If path matches but method doesn't, return 405 with an `Allow` header listing all valid methods for that path
5. If no path matches, call the `not_found_handler`

### Specificity Scoring
- Static segments (e.g. `users`): 100 points
- Named parameters (e.g. `:id`): 10 points
- Wildcards (e.g. `*`): 1 point
- Total score is sum across all segments

### Pattern Syntax
| Pattern | Description |
|---------|-------------|
| `/users` | Static segment — matches literally |
| `/users/:id` | Named parameter — matches any single path segment, value stored in `params.get("id")` |
| `/users/:id[u64]` | Typed parameter — matches and validates as the specified integer type |
| `/static/*` | Wildcard — matches remaining path segments, captured under `"*"` param name |

### Route Groups
```zig
const routes = .{
    zypher.router.Router.group("/api", .{
        zypher.router.Router.route(.get, "/users", listHandler),
        zypher.router.Router.route(.post, "/users", createHandler),
    }),
};
// Creates: GET  /api/users → listHandler
//          POST /api/users → createHandler
```

### Full Example
```zig
const zypher = @import("zypher");

fn listHandler(req: *zypher.core.Request, res: *zypher.core.Response) void {
    res.json(.{ .users = &.{} }) catch {};
}

fn getUserHandler(req: *zypher.core.Request, res: *zypher.core.Response) void {
    const id = req.params.get("id") orelse "";
    res.json(.{ .id = id }) catch {};
}

fn notFound(req: *zypher.core.Request, res: *zypher.core.Response) void {
    _ = res.status(404);
    res.text("Not Found") catch {};
}

const routes = .{
    zypher.router.Router.route(.get, "/api/users", listHandler),
    zypher.router.Router.route(.get, "/api/users/:id", getUserHandler),
};

var router = zypher.router.Router.init(routes, notFound);
app.routerHandler(router.dispatch);
```
