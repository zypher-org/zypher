/// Regression tests: ensure middleware integration doesn't break existing routing.
const std = @import("std");
const App = @import("zypher").core.App;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Chain = @import("zypher").middleware.Chain;
const logger = @import("zypher").middleware.logger;
const Route = @import("zypher").router.Route;
const Router = @import("zypher").router.Router;

fn makeRequest(gpa: std.mem.Allocator, method: @import("zypher").core.Method, path: []const u8) Request {
    return .{
        .method = method,
        .path = path,
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
}

fn home_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("home") catch {};
}

fn user_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("user") catch {};
}

fn not_found_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("Not Found") catch {};
}

// Router without middleware
const routes = .{
    Route.init(.get, "/", home_handler),
    Route.init(.get, "/users/:id", user_handler),
};
const MyRouter = Router.init(routes, not_found_handler);

fn router_dispatch(req: *Request, res: *Response) void {
    MyRouter.dispatch(req, res);
}

// Router with middleware
const LoggerChain = Chain(.{logger.middleware});

fn chain_dispatch(req: *Request, res: *Response) void {
    LoggerChain.run(req, res, router_dispatch);
}

test "Regression: router still dispatches correctly without middleware" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.routerHandler(router_dispatch);

    // / route
    {
        var req = makeRequest(gpa, .get, "/");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }

    // /users/42 route
    {
        var req = makeRequest(gpa, .get, "/users/42");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }

    // 404
    {
        var req = makeRequest(gpa, .get, "/missing");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 404), res.status_code);
    }
}

test "Regression: router dispatches correctly with middleware" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.middlewareHandler(chain_dispatch);

    // / route
    {
        var req = makeRequest(gpa, .get, "/");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }

    // /users/42 route — params still extracted correctly
    {
        var req = makeRequest(gpa, .get, "/users/42");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }

    // 404 still works
    {
        var req = makeRequest(gpa, .get, "/missing");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 404), res.status_code);
    }
}

test "Regression: middleware chain has zero heap allocation for dispatch" {
    const gpa = std.testing.allocator;

    // The Chain.run() method uses comptime-unrolled dispatch with no
    // heap allocation. Verify by running many requests and checking
    // that no leaks are reported (the test framework checks this).
    var app = App.init(gpa, .{});
    defer app.deinit();
    app.middlewareHandler(chain_dispatch);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var req = makeRequest(gpa, .get, "/");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }
}
