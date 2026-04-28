/// Unit tests for zypher Static file middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const static_mw = @import("zypher").middleware.static;
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

test "Static: path traversal is rejected with 403" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = "/tmp/zypher-test-static" })});

    var req = makeRequest(gpa, .get, "/../../etc/passwd");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}

test "Static: non-prefix path passes through to handler" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = "/tmp/zypher-test-static", .prefix = "/static" })});

    var req = makeRequest(gpa, .get, "/api/data");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    // /api/data doesn't start with /static prefix, so passes through
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "Static: MIME type detection by extension" {
    const actual = static_mw.detectMime("style.css");
    try std.testing.expectEqualStrings("text/css", actual);

    const js = static_mw.detectMime("app.js");
    try std.testing.expectEqualStrings("application/javascript", js);

    const html = static_mw.detectMime("index.html");
    try std.testing.expectEqualStrings("text/html; charset=utf-8", html);

    const unknown = static_mw.detectMime("data.bin");
    try std.testing.expectEqualStrings("application/octet-stream", unknown);
}
