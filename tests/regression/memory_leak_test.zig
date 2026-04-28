/// Regression test: request parsing must not leak memory.
/// Uses std.testing.allocator (which detects leaks) to verify all allocations are freed.
const std = @import("std");
const App = @import("zypher").core.App;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Method = @import("zypher").core.Method;

test "request parsing: no memory leak on simple GET" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();

    const head = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    req.deinit();
}

test "request parsing: no memory leak on GET with query string" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();

    const head = "GET /search?q=zig&lang=en HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    req.deinit();
}

test "request parsing: no memory leak on POST with multiple headers" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();

    const head = "POST /submit HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\nContent-Length: 42\r\nX-Request-Id: abc123\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    req.deinit();
}

test "request parsing: no memory leak on repeated parse-and-free cycle" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();

    const heads = [_][]const u8{
        "GET / HTTP/1.1\r\nHost: a\r\n\r\n",
        "POST /data HTTP/1.1\r\nHost: b\r\nContent-Length: 0\r\n\r\n",
        "GET /path?q=test HTTP/1.1\r\nHost: c\r\nAccept: text/html\r\n\r\n",
    };

    for (heads) |head| {
        var req = try app.buildRequestFromHead(head);
        req.deinit();
    }
}

test "response: no memory leak after text/html/json body" {
    const gpa = std.testing.allocator;

    var res = Response.init(gpa);
    try res.text("hello");
    res.deinit();

    var res2 = Response.init(gpa);
    try res2.html("<b>bold</b>");
    res2.deinit();

    var res3 = Response.init(gpa);
    try res3.json("{\"ok\":true}");
    res3.deinit();
}

test "response: no memory leak with cookie set" {
    const gpa = std.testing.allocator;

    var res = Response.init(gpa);
    _ = res.setCookie(.{
        .name = "sid",
        .value = "abc123",
        .path = "/",
        .http_only = true,
        .secure = true,
        .same_site = .Strict,
    });
    res.deinit();
}

test "full round-trip: no memory leak on request + response lifecycle" {
    const gpa = std.testing.allocator;

    const test_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            _ = res.status(200);
            res.text("ok") catch {};
        }
    }.handler;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.handler(test_handler);

    const head = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);
}
