/// Regression test: Router dispatch does not allocate on matched routes.
const std = @import("std");
const Router = @import("zypher").router.Router;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Method = @import("zypher").core.Method;

fn hello_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("hello") catch {};
}

fn user_handler(req: *Request, res: *Response) void {
    if (req.params.get("id")) |id| {
        _ = res.status(200);
        res.text(id) catch {};
    }
}

fn not_found_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("not found") catch {};
}

test "router dispatch: no memory leak on matched route with params" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
        Router.route(.get, "/users/:id", user_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .get,
        .path = "/users/42",
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();

    router.dispatch(&req, &res);
}

test "router dispatch: no memory leak on 404 unmatched route" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .get,
        .path = "/nonexistent",
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();

    router.dispatch(&req, &res);
}

test "router dispatch: no memory leak on 405 method mismatch" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/resource", hello_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var req: Request = .{
        .method = .post,
        .path = "/resource",
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();

    router.dispatch(&req, &res);
}

test "router dispatch: no memory leak on repeated dispatch cycles" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
        Router.route(.get, "/users/:id", user_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    const paths = [_][]const u8{ "/", "/users/1", "/users/99", "/nonexistent" };
    for (paths) |path| {
        var req: Request = .{
            .method = .get,
            .path = path,
            .query = std.StringHashMap([]const u8).init(gpa),
            .headers = std.StringHashMap([]const u8).init(gpa),
            .body = &.{},
            .allocator = gpa,
        };
        defer req.deinit();

        var res = Response.init(gpa);
        defer res.deinit();

        router.dispatch(&req, &res);
    }
}
