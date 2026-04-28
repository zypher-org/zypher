/// Unit tests for zypher Compression middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const compress = @import("zypher").middleware.compress;
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

fn text_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("Hello, World! This is a test response that should be compressible.") catch {};
}

test "Compression: no Accept-Encoding passes through uncompressed" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{compress.middleware});

    var req = makeRequest(gpa, .get, "/test");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, text_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    // No Content-Encoding should be set
    const encoding = res.headers.get("Content-Encoding");
    try std.testing.expect(encoding == null);
}

test "Compression: gzip accepted sets Content-Encoding header" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{compress.middleware});

    var req = makeRequest(gpa, .get, "/test");
    try req.headers.put("Accept-Encoding", "gzip");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, text_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    const encoding = res.headers.get("Content-Encoding");
    try std.testing.expect(encoding != null);
    try std.testing.expectEqualStrings("gzip", encoding.?);
}
