/// Unit tests for zypher Router — comptime route registration and runtime dispatch.
const std = @import("std");
const Router = @import("zypher").router.Router;
const Method = @import("zypher").core.Method;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const RouteParams = @import("zypher").router.RouteParams;

// ── Test handlers ───────────────────────────────────────────────────

fn hello_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("hello") catch {};
}

fn user_handler(req: *Request, res: *Response) void {
    if (req.params.get("id")) |id| {
        _ = res.status(200);
        res.text(id) catch {};
    } else {
        _ = res.status(400);
        res.text("missing id") catch {};
    }
}

fn create_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(201);
    res.text("created") catch {};
}

fn not_found_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("not found") catch {};
}

// ── Route registration ──────────────────────────────────────────────

test "Router: register and dispatch GET route" {
    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .get,
        .path = "/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = @import("zypher").core.Response.init(std.testing.allocator);
    defer res.deinit();

    router.dispatch(&req, &res);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "Router: register and dispatch POST route" {
    const routes = comptime .{
        Router.route(.post, "/create", create_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .post,
        .path = "/create",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = @import("zypher").core.Response.init(std.testing.allocator);
    defer res.deinit();

    router.dispatch(&req, &res);
    try std.testing.expectEqual(@as(u16, 201), res.status_code);
}

test "Router: dispatch to correct handler among multiple routes" {
    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
        Router.route(.get, "/users/:id", user_handler),
        Router.route(.post, "/create", create_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .get,
        .path = "/users/42",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = @import("zypher").core.Response.init(std.testing.allocator);
    defer res.deinit();

    router.dispatch(&req, &res);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    // Params should be extracted
    try std.testing.expectEqualStrings("42", req.params.get("id").?);
}

// ── 404 for unmatched routes ────────────────────────────────────────

test "Router: unmatched route returns 404" {
    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .get,
        .path = "/nonexistent",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = @import("zypher").core.Response.init(std.testing.allocator);
    defer res.deinit();

    router.dispatch(&req, &res);
    try std.testing.expectEqual(@as(u16, 404), res.status_code);
}

// ── 405 for method mismatch ─────────────────────────────────────────

test "Router: method mismatch returns 405 with Allow header" {
    const routes = comptime .{
        Router.route(.get, "/resource", hello_handler),
        Router.route(.put, "/resource", create_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .post,
        .path = "/resource",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = @import("zypher").core.Response.init(std.testing.allocator);
    defer res.deinit();

    router.dispatch(&req, &res);
    try std.testing.expectEqual(@as(u16, 405), res.status_code);
    // Allow header should list the allowed methods
    const allow = res.headers.get("Allow");
    try std.testing.expect(allow != null);
    try std.testing.expect(std.mem.indexOf(u8, allow.?, "GET") != null);
    try std.testing.expect(std.mem.indexOf(u8, allow.?, "PUT") != null);
}
