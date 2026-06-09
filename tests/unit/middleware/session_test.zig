const std = @import("std");
const zypher = @import("zypher");

const Chain = zypher.middleware.Chain;
const session_mw = zypher.middleware.session;
const SessionStore = zypher.auth.session.SessionStore;
const Request = zypher.core.Request;
const Response = zypher.core.Response;

fn makeRequest(gpa: std.mem.Allocator) Request {
    return .{
        .method = .get,
        .path = "/",
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
}

fn okHandler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
}

test "session middleware can emit non-secure cookie for local HTTP" {
    const gpa = std.testing.allocator;

    var store = SessionStore.init(gpa);
    defer store.deinit();
    session_mw.setStore(&store);
    session_mw.setCookieConfig(.{
        .httponly = true,
        .secure = false,
        .samesite = "Strict",
        .path = "/",
        .max_age = 86400,
    });
    defer session_mw.resetCookieConfig();

    const MyChain = comptime Chain(.{session_mw.middleware});
    var req = makeRequest(gpa);
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, okHandler);

    const cookie = res.headers.get("Set-Cookie").?;
    try std.testing.expect(std.mem.indexOf(u8, cookie, "zypher_session=") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie, "HttpOnly") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie, "SameSite=Strict") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie, "Secure") == null);
}
