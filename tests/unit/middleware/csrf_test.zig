/// Unit tests for zypher CSRF middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const csrf = @import("zypher").middleware.csrf;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const SessionStore = @import("zypher").auth.session.SessionStore;

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

fn next_handler(io: std.Io, req: *Request, res: *Response) void {
    _ = io;
    ok_handler(req, res);
}

test "CSRF: GET passes through without session" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{csrf.middleware});

    var req = makeRequest(gpa, .get, "/page");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    // No session, so no CSRF token is set — request still passes
    const token = res.headers.get("X-CSRF-Token");
    try std.testing.expect(token == null);
}

test "CSRF: POST with valid session-backed token passes" {
    const gpa = std.testing.allocator;

    var store = SessionStore.init(gpa);
    defer store.deinit();

    var session = store.create(std.testing.io);
    defer session.deinit(gpa);

    // First, GET to establish a token in the session
    var get_req = makeRequest(gpa, .get, "/page");
    defer get_req.deinit();
    get_req.user = @ptrCast(&session);
    var get_res = Response.init(gpa);
    defer get_res.deinit();
    csrf.middleware(std.testing.io, &get_req, &get_res, next_handler);
    const token = get_res.headers.get("X-CSRF-Token").?;

    // Now POST with the token
    var post_req = makeRequest(gpa, .post, "/submit");
    defer post_req.deinit();
    post_req.user = @ptrCast(&session);
    try post_req.headers.put("X-CSRF-Token", token);
    var post_res = Response.init(gpa);
    defer post_res.deinit();

    csrf.middleware(std.testing.io, &post_req, &post_res, next_handler);

    try std.testing.expectEqual(@as(u16, 200), post_res.status_code);
}

test "CSRF: POST with valid form token passes" {
    const gpa = std.testing.allocator;

    var store = SessionStore.init(gpa);
    defer store.deinit();

    var session = store.create(std.testing.io);
    defer session.deinit(gpa);

    // GET to establish a token
    var get_req = makeRequest(gpa, .get, "/page");
    defer get_req.deinit();
    get_req.user = @ptrCast(&session);
    var get_res = Response.init(gpa);
    defer get_res.deinit();
    csrf.middleware(std.testing.io, &get_req, &get_res, next_handler);

    const token = session.get("_csrf_token").?;

    // POST with the token as a form value
    var post_req = makeRequest(gpa, .post, "/submit");
    defer post_req.deinit();
    post_req.user = @ptrCast(&session);
    try post_req.query.put("_csrf", token);
    var post_res = Response.init(gpa);
    defer post_res.deinit();

    csrf.middleware(std.testing.io, &post_req, &post_res, next_handler);

    try std.testing.expectEqual(@as(u16, 200), post_res.status_code);
}

test "CSRF: POST without token returns 403" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{csrf.middleware});

    var req = makeRequest(gpa, .post, "/submit");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, ok_handler);

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

    MyChain.run(std.testing.io, &req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}

test "CSRF: session-backed token is stored and required when session is attached" {
    const gpa = std.testing.allocator;

    var store = SessionStore.init(gpa);
    defer store.deinit();

    var session = store.create(std.testing.io);
    defer session.deinit(gpa);

    var get_req = makeRequest(gpa, .get, "/page");
    defer get_req.deinit();
    get_req.user = @ptrCast(&session);
    var get_res = Response.init(gpa);
    defer get_res.deinit();

    csrf.middleware(std.testing.io, &get_req, &get_res, next_handler);
    const token = get_res.headers.get("X-CSRF-Token").?;
    try std.testing.expectEqualStrings(token, session.get("_csrf_token").?);
    try std.testing.expectEqual(@as(usize, 64), token.len);

    var post_req = makeRequest(gpa, .post, "/submit");
    defer post_req.deinit();
    post_req.user = @ptrCast(&session);
    try post_req.headers.put("X-CSRF-Token", token);
    var post_res = Response.init(gpa);
    defer post_res.deinit();

    csrf.middleware(std.testing.io, &post_req, &post_res, next_handler);
    try std.testing.expectEqual(@as(u16, 200), post_res.status_code);

    var bad_req = makeRequest(gpa, .post, "/submit");
    defer bad_req.deinit();
    bad_req.user = @ptrCast(&session);
    try bad_req.headers.put("X-CSRF-Token", "invalid-token-value");
    var bad_res = Response.init(gpa);
    defer bad_res.deinit();

    csrf.middleware(std.testing.io, &bad_req, &bad_res, next_handler);
    try std.testing.expectEqual(@as(u16, 403), bad_res.status_code);
}
