/// Unit tests for zypher CORS middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const cors = @import("zypher").middleware.cors;
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

test "CORS: adds Allow-Origin header on normal request" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{cors.middleware});

    var req = makeRequest(gpa, .get, "/api/data");
    try req.headers.put("Origin", "http://example.com");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    const origin = res.headers.get("Access-Control-Allow-Origin");
    try std.testing.expect(origin != null);
    try std.testing.expectEqualStrings("http://example.com", origin.?);
}

test "CORS: handles preflight OPTIONS request" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{cors.middleware});

    var req = makeRequest(gpa, .options, "/api/data");
    try req.headers.put("Origin", "http://example.com");
    try req.headers.put("Access-Control-Request-Method", "POST");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    // Preflight should short-circuit with 204
    try std.testing.expectEqual(@as(u16, 204), res.status_code);
    const origin = res.headers.get("Access-Control-Allow-Origin");
    try std.testing.expect(origin != null);
    const methods = res.headers.get("Access-Control-Allow-Methods");
    try std.testing.expect(methods != null);
    const headers = res.headers.get("Access-Control-Allow-Headers");
    try std.testing.expect(headers != null);
}

test "CORS: blocked origin gets 403" {
    const gpa = std.testing.allocator;

    // Create a CORS config that only allows http://allowed.com
    const MyChain = comptime Chain(.{cors.middlewareWith(.{ .allowed_origins = &.{"http://allowed.com"} })});

    var req = makeRequest(gpa, .get, "/api/data");
    try req.headers.put("Origin", "http://evil.com");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}

test "CORS: allowed origin passes through" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{cors.middlewareWith(.{ .allowed_origins = &.{"http://allowed.com"} })});

    var req = makeRequest(gpa, .get, "/api/data");
    try req.headers.put("Origin", "http://allowed.com");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    const origin = res.headers.get("Access-Control-Allow-Origin");
    try std.testing.expect(origin != null);
    try std.testing.expectEqualStrings("http://allowed.com", origin.?);
}
