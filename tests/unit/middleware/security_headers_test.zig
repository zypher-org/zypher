/// Tests for security headers middleware.
const std = @import("std");
const zypher = @import("zypher");
const Request = zypher.core.Request;
const Response = zypher.core.Response;

fn makeRequest(gpa: std.mem.Allocator, method: zypher.core.Method, path: []const u8) Request {
    return .{
        .method = method,
        .path = path,
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
}

fn dummyHandlerNext(io: std.Io, req: *Request, res: *Response) void {
    _ = io;
    _ = req;
    res.text("ok") catch {};
}

test "security headers: sets X-Content-Type-Options" {
    const gpa = std.testing.allocator;
    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    zypher.middleware.security_headers.middleware(std.testing.io, &req, &res, dummyHandlerNext);

    const ct = res.headers.get("X-Content-Type-Options");
    try std.testing.expectEqualStrings("nosniff", ct.?);
}

test "security headers: sets X-Frame-Options" {
    const gpa = std.testing.allocator;
    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    zypher.middleware.security_headers.middleware(std.testing.io, &req, &res, dummyHandlerNext);

    const xfo = res.headers.get("X-Frame-Options");
    try std.testing.expectEqualStrings("DENY", xfo.?);
}

test "security headers: sets Referrer-Policy" {
    const gpa = std.testing.allocator;
    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    zypher.middleware.security_headers.middleware(std.testing.io, &req, &res, dummyHandlerNext);

    const rp = res.headers.get("Referrer-Policy");
    try std.testing.expectEqualStrings("strict-origin-when-cross-origin", rp.?);
}

test "security headers: sets X-XSS-Protection" {
    const gpa = std.testing.allocator;
    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    zypher.middleware.security_headers.middleware(std.testing.io, &req, &res, dummyHandlerNext);

    const xxp = res.headers.get("X-XSS-Protection");
    try std.testing.expectEqualStrings("0", xxp.?);
}

test "security headers: all four headers present" {
    const gpa = std.testing.allocator;
    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    zypher.middleware.security_headers.middleware(std.testing.io, &req, &res, dummyHandlerNext);

    try std.testing.expect(res.headers.get("X-Content-Type-Options") != null);
    try std.testing.expect(res.headers.get("X-Frame-Options") != null);
    try std.testing.expect(res.headers.get("Referrer-Policy") != null);
    try std.testing.expect(res.headers.get("X-XSS-Protection") != null);
}

test "security headers: handler still runs (body set by handler)" {
    const gpa = std.testing.allocator;
    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    zypher.middleware.security_headers.middleware(std.testing.io, &req, &res, dummyHandlerNext);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
    try std.testing.expectEqualStrings("ok", res.body.?);
}
