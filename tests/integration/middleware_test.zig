/// Integration tests: middleware chain wired into App dispatch.
const std = @import("std");
const App = @import("zypher").core.App;
const Server = @import("zypher").core.Server;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Chain = @import("zypher").middleware.Chain;
const logger = @import("zypher").middleware.logger;
const cors = @import("zypher").middleware.cors;
const csrf = @import("zypher").middleware.csrf;
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

// ── Test handlers ──────────────────────────────────────────────────

fn home_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("home") catch {};
}

fn api_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("api data") catch {};
}

// ── Middleware + App wiring ─────────────────────────────────────────

/// Create a middleware-wrapped handler that runs logger + CSRF before the terminal handler.
const TestChain = Chain(.{ logger.middleware, csrf.middleware });

fn middleware_dispatch(req: *Request, res: *Response) void {
    TestChain.run(req, res, home_handler);
}

fn not_found_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("Not Found") catch {};
}

// Router + chain dispatch
const router_routes = .{
    Route.init(.get, "/", home_handler),
    Route.init(.get, "/api", api_handler),
};
const MyRouter = Router.init(router_routes, not_found_handler);
const LoggerChain = Chain(.{logger.middleware});

fn router_dispatch(req: *Request, res: *Response) void {
    MyRouter.dispatch(req, res);
}

fn chain_dispatch(req: *Request, res: *Response) void {
    LoggerChain.run(req, res, router_dispatch);
}

// CORS chain dispatch
const CorsChain = Chain(.{cors.middleware});

fn cors_dispatch(req: *Request, res: *Response) void {
    CorsChain.run(req, res, home_handler);
}

test "Integration: middleware chain wired into App dispatch" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.middlewareHandler(middleware_dispatch);

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    // CSRF token should be set by middleware
    const token = res.headers.get("X-CSRF-Token");
    try std.testing.expect(token != null);
}

test "Integration: middleware + router together" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.middlewareHandler(chain_dispatch);

    // Test / route
    {
        var req = makeRequest(gpa, .get, "/");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }

    // Test /api route
    {
        var req = makeRequest(gpa, .get, "/api");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }

    // Test 404
    {
        var req = makeRequest(gpa, .get, "/missing");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        app.handleRequest(&req, &res);
        try std.testing.expectEqual(@as(u16, 404), res.status_code);
    }
}

test "Integration: CORS middleware short-circuits preflight" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.middlewareHandler(cors_dispatch);

    var req = makeRequest(gpa, .options, "/api");
    try req.headers.put("Origin", "http://example.com");
    try req.headers.put("Access-Control-Request-Method", "POST");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 204), res.status_code);
    const origin = res.headers.get("Access-Control-Allow-Origin");
    try std.testing.expect(origin != null);
}
