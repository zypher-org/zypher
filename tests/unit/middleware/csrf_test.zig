/// Unit tests for zypher CSRF middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const csrf = @import("zypher").middleware.csrf;
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

test "CSRF: GET passes through without token" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{csrf.middleware});

    var req = makeRequest(gpa, .get, "/page");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    // CSRF token should be set in response
    const token = res.headers.get("X-CSRF-Token");
    try std.testing.expect(token != null);
}

test "CSRF: POST with valid token passes" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{csrf.middleware});

    // First, simulate a GET to get a token
    var get_req = makeRequest(gpa, .get, "/page");
    defer get_req.deinit();
    var get_res = Response.init(gpa);
    defer get_res.deinit();
    MyChain.run(&get_req, &get_res, ok_handler);
    const token = get_res.headers.get("X-CSRF-Token").?;

    // Now POST with the token
    var post_req = makeRequest(gpa, .post, "/submit");
    try post_req.headers.put("X-CSRF-Token", token);
    defer post_req.deinit();
    var post_res = Response.init(gpa);
    defer post_res.deinit();

    MyChain.run(&post_req, &post_res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), post_res.status_code);
}

test "CSRF: POST without token returns 403" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{csrf.middleware});

    var req = makeRequest(gpa, .post, "/submit");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}

test "CSRF: POST with wrong token returns 403" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{csrf.middleware});

    var req = makeRequest(gpa, .post, "/submit");
    try req.headers.put("X-CSRF-Token", "invalid-token");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}
