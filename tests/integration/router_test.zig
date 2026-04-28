/// Integration test: Router wired to App — HTTP request parsing + route dispatch + response.
const std = @import("std");
const App = @import("zypher").core.App;
const Router = @import("zypher").router.Router;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Method = @import("zypher").core.Method;

fn hello_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("Hello from Zypher!") catch {};
}

fn user_handler(req: *Request, res: *Response) void {
    if (req.params.getAs(u64, "id")) |id| {
        _ = res.status(200);
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "User {d}", .{id}) catch "User ?";
        res.text(msg) catch {};
    } else |_| {
        _ = res.status(400);
        res.text("invalid user id") catch {};
    }
}

fn not_found_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("Not Found") catch {};
}

test "router integration: GET /users/42 dispatches to handler with id=42" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
        Router.route(.get, "/users/:id", user_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.routerHandler(struct {
        fn dispatch(req: *Request, res: *Response) void {
            router.dispatch(req, res);
        }
    }.dispatch);

    // Simulate a raw HTTP request
    const head = "GET /users/42 HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "router integration: unmatched route returns 404" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/", hello_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.routerHandler(struct {
        fn dispatch(req: *Request, res: *Response) void {
            router.dispatch(req, res);
        }
    }.dispatch);

    const head = "GET /nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 404), res.status_code);
}

test "router integration: method mismatch returns 405" {
    const gpa = std.testing.allocator;

    const routes = comptime .{
        Router.route(.get, "/resource", hello_handler),
    };
    const router = comptime Router.init(routes, not_found_handler);

    var app = App.init(gpa, .{});
    defer app.deinit();
    app.routerHandler(struct {
        fn dispatch(req: *Request, res: *Response) void {
            router.dispatch(req, res);
        }
    }.dispatch);

    const head = "POST /resource HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var req = try app.buildRequestFromHead(head);
    defer req.deinit();

    var res = Response.init(gpa);
    defer res.deinit();
    app.handleRequest(&req, &res);

    try std.testing.expectEqual(@as(u16, 405), res.status_code);
}
