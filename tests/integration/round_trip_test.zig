/// Integration test: full round-trip GET 200.
/// Parses a raw HTTP request head, dispatches through App handler, serializes response.
const std = @import("std");
const App = @import("zypher").core.App;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Method = @import("zypher").core.Method;

test "full round-trip: GET / 200" {
    const gpa = std.testing.allocator;

    // 1. Create an App with a handler
    const hello_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            _ = res.status(200);
            res.text("Hello from Zypher!") catch {};
        }
    }.handler;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.handler(hello_handler);

    // 2. Simulate a raw HTTP request head
    const head = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nAccept: text/plain\r\n\r\n";

    // 3. Build a zypher Request from the raw head
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    // 4. Verify request was parsed correctly
    try std.testing.expectEqual(Method.get, req.method);
    try std.testing.expectEqualStrings("/", req.path);
    try std.testing.expectEqualStrings("localhost:8080", req.headers.get("Host").?);
    try std.testing.expectEqualStrings("text/plain", req.headers.get("Accept").?);

    // 5. Dispatch through the handler
    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);

    // 6. Verify response
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expectEqualStrings("Hello from Zypher!", res.body.?);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", res.headers.get("Content-Type").?);

    // 7. Serialize the response
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try res.send(gpa, &buf);

    // 8. Verify serialized response starts with status line and contains headers + body
    const output = buf.items;
    try std.testing.expect(std.mem.startsWith(u8, output, "HTTP/1.1 200 OK\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "Content-Type: text/plain; charset=utf-8\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Content-Length: 18\r\n") != null);
    try std.testing.expect(std.mem.endsWith(u8, output, "Hello from Zypher!"));
}

test "full round-trip: POST /submit 201" {
    const gpa = std.testing.allocator;

    const submit_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            _ = res.status(201);
            res.json("{\"created\":true}") catch {};
        }
    }.handler;

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.handler(submit_handler);

    const head = "POST /submit HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\nContent-Length: 0\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    try std.testing.expectEqual(Method.post, req.method);
    try std.testing.expectEqualStrings("/submit", req.path);

    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 201), res.status_code);
    try std.testing.expectEqualStrings("application/json", res.headers.get("Content-Type").?);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try res.send(gpa, &buf);
    try std.testing.expect(std.mem.startsWith(u8, buf.items, "HTTP/1.1 201 Created\r\n"));
}

test "full round-trip: GET /missing 404 when no handler" {
    const gpa = std.testing.allocator;

    var app = App.init(gpa, .{});
    defer app.deinit();
    // No handler registered

    const head = "GET /missing HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 404), res.status_code);
}
