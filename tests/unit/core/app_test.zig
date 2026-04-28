/// Unit tests for zypher App entry point.
const std = @import("std");
const App = @import("zypher").core.App;
const Server = @import("zypher").core.Server;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Method = @import("zypher").core.Method;

// ── App creation ─────────────────────────────────────────────────

test "App.init creates an App with default config" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();
    try std.testing.expectEqual(@as(u16, 8080), app.server.config.port);
    try std.testing.expectEqualStrings("127.0.0.1", app.server.config.host);
}

test "App.init with custom config" {
    var app = App.init(std.testing.allocator, .{
        .host = "0.0.0.0",
        .port = 3000,
    });
    defer app.deinit();
    try std.testing.expectEqual(@as(u16, 3000), app.server.config.port);
    try std.testing.expectEqualStrings("0.0.0.0", app.server.config.host);
}

// ── Handler registration ─────────────────────────────────────────

test "App.handler sets the request handler" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();

    const test_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            _ = res.status(200);
            res.text("ok") catch {};
        }
    }.handler;

    app.handler(test_handler);
    try std.testing.expect(app.handler_fn != null);
}

// ── BuildRequest from raw HTTP ───────────────────────────────────

test "App.buildRequestFromHead parses a simple GET request" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();

    const head = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();
    try std.testing.expectEqual(Method.get, req.method);
    try std.testing.expectEqualStrings("/hello", req.path);
    try std.testing.expectEqualStrings("localhost", req.headers.get("Host").?);
}

test "App.buildRequestFromHead parses POST with headers" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();

    const head = "POST /submit HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();
    try std.testing.expectEqual(Method.post, req.method);
    try std.testing.expectEqualStrings("/submit", req.path);
    try std.testing.expectEqualStrings("application/json", Request.getHeaderCI(&req.headers, "content-type").?);
    try std.testing.expectEqualStrings("13", Request.getHeaderCI(&req.headers, "content-length").?);
}

test "App.buildRequestFromHead rejects malformed request" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();

    const head = "GARBAGE";
    const result = app.buildRequestFromHead(head);
    try std.testing.expectError(error.BadRequest, result);
}

// ── Handle request ───────────────────────────────────────────────

test "App.handleRequest calls the registered handler" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();

    const test_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            _ = res.status(201);
            res.text("created") catch {};
        }
    }.handler;
    app.handler(test_handler);

    var req: Request = .{
        .method = .post,
        .path = "/items",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    app.handleRequest(&req, &res);
    try std.testing.expectEqual(@as(u16, 201), res.status_code);
}

test "App.handleRequest returns 404 when no handler registered" {
    var app = App.init(std.testing.allocator, .{});
    defer app.deinit();

    var req: Request = .{
        .method = .get,
        .path = "/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    app.handleRequest(&req, &res);
    try std.testing.expectEqual(@as(u16, 404), res.status_code);
}
