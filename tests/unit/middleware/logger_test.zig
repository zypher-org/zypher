/// Unit tests for zypher Logger middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const logger = @import("zypher").middleware.logger;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;

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

fn ok_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("ok") catch {};
}

fn not_found_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("not found") catch {};
}

fn created_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(201);
    res.text("created") catch {};
}

test "Logger: logs method, path, status code, and duration" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{logger.middleware});

    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "Logger: logs 404 status from handler" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{logger.middleware});

    var req = makeRequest(gpa, .get, "/missing");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, not_found_handler);

    try std.testing.expectEqual(@as(u16, 404), res.status_code);
}

test "Logger: works with POST method" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{logger.middleware});

    var req = makeRequest(gpa, .post, "/items");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, created_handler);

    try std.testing.expectEqual(@as(u16, 201), res.status_code);
}
