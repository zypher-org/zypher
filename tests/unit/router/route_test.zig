/// Unit tests for zypher Route definition and path matching.
const std = @import("std");
const Route = @import("zypher").router.Route;
const RouteParams = @import("zypher").router.RouteParams;
const Method = @import("zypher").core.Method;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;

// ── Static route matching ──────────────────────────────────────────

test "Route.matchPath: static route / matches /" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/", "/", &params);
    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 0), params.count());
}

test "Route.matchPath: static route / does not match /foo" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/", "/foo", &params);
    try std.testing.expect(!matched);
}

test "Route.matchPath: static route /hello matches /hello" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/hello", "/hello", &params);
    try std.testing.expect(matched);
}

test "Route.matchPath: static route /hello does not match /hello/world" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/hello", "/hello/world", &params);
    try std.testing.expect(!matched);
}

// ── Typed param matching ───────────────────────────────────────────

test "Route.matchPath: /users/:id extracts id as string" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/users/:id", "/users/42", &params);
    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 1), params.count());
    try std.testing.expectEqualStrings("42", params.get("id").?);
}

test "Route.matchPath: /org/:org/repo/:repo extracts both params" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/org/:org/repo/:repo", "/org/zypher/repo/core", &params);
    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 2), params.count());
    try std.testing.expectEqualStrings("zypher", params.get("org").?);
    try std.testing.expectEqualStrings("core", params.get("repo").?);
}

test "Route.matchPath: /posts/:id with non-matching path returns false" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/posts/:id", "/posts", &params);
    try std.testing.expect(!matched);
}

// ── Wildcard matching ──────────────────────────────────────────────

test "Route.matchPath: /static/* matches any prefix" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/static/*", "/static/css/style.css", &params);
    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 1), params.count());
    try std.testing.expectEqualStrings("css/style.css", params.get("*").?);
}

test "Route.matchPath: /static/* matches /static/ with empty wildcard" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/static/*", "/static/", &params);
    try std.testing.expect(matched);
}

test "Route.matchPath: /static/* does not match /static (no trailing slash)" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const matched = Route.matchPath("/static/*", "/static", &params);
    try std.testing.expect(!matched);
}

// ── Route struct ────────────────────────────────────────────────────

test "Route.init creates a route with method, pattern, and handler" {
    const test_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            _ = res.status(200);
        }
    }.handler;

    const route = Route.init(.get, "/hello", test_handler);
    try std.testing.expectEqual(Method.get, route.method);
    try std.testing.expectEqualStrings("/hello", route.pattern);
}

// ── Compile-time pattern validation ────────────────────────────────

test "Route.validatePattern: valid patterns pass" {
    try Route.validatePattern("/");
    try Route.validatePattern("/hello");
    try Route.validatePattern("/users/:id");
    try Route.validatePattern("/org/:org/repo/:repo");
    try Route.validatePattern("/static/*");
}

test "Route.validatePattern: duplicate param names return error" {
    try std.testing.expectError(error.DuplicateParam, Route.validatePattern("/users/:id/posts/:id"));
}

test "Route.validatePattern: wildcard must be last segment" {
    try std.testing.expectError(error.InvalidPattern, Route.validatePattern("/static/*/foo"));
}

test "Route.validatePattern: empty pattern is invalid" {
    try std.testing.expectError(error.InvalidPattern, Route.validatePattern(""));
}

test "Route.validatePattern: pattern must start with /" {
    try std.testing.expectError(error.InvalidPattern, Route.validatePattern("hello"));
}
