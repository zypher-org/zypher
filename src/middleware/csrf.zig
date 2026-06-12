/// zypher CSRF middleware — Cross-Site Request Forgery protection.
///
/// For GET/HEAD/OPTIONS: generates a token and sets it in the X-CSRF-Token response header.
/// For POST/PUT/DELETE/PATCH: validates the X-CSRF-Token request header against the stored token.
/// If missing or mismatched, returns 403.
///
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const Session = @import("../auth/session.zig").Session;
const log = std.log.scoped(.csrf);

const session_key = "_csrf_token";

fn randomBytes(buf: []u8) !void {
    if (buf.len == 0) return;

    if (@import("builtin").os.tag == .linux) {
        var filled: usize = 0;
        while (filled < buf.len) {
            const remaining = buf[filled..];
            const rc = std.os.linux.getrandom(remaining.ptr, remaining.len, 0);
            switch (std.posix.errno(rc)) {
                .SUCCESS => {
                    const n: usize = @intCast(rc);
                    if (n == 0) return error.EntropyUnavailable;
                    filled += n;
                },
                .INTR => continue,
                else => return error.EntropyUnavailable,
            }
        }
        return;
    }

    if (@import("builtin").link_libc and @TypeOf(std.posix.system.arc4random_buf) != void) {
        std.posix.system.arc4random_buf(buf.ptr, buf.len);
        return;
    }

    return error.EntropyUnavailable;
}

/// Return the request CSRF token, creating and storing one in the session.
pub fn ensureToken(req: *Request) ![]const u8 {
    const user_ptr = req.user orelse return error.CsrfSessionUnavailable;
    const session: *Session = @ptrCast(@alignCast(user_ptr));
    if (session.get(session_key)) |token| return token;

    var random: [32]u8 = undefined;
    try randomBytes(&random);
    const hex = std.fmt.bytesToHex(random, .lower);
    try session.put(req.allocator, session_key, &hex);
    return session.get(session_key) orelse error.CsrfTokenUnavailable;
}

/// Validate a token against the request session.
pub fn validateTokenForRequest(req: *Request, token: []const u8) bool {
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        const expected = session.get(session_key) orelse return false;
        if (expected.len != token.len or expected.len != 64) return false;
        return std.crypto.timing_safe.eql([64]u8, expected[0..64].*, token[0..64].*);
    }
    return false;
}

/// CSRF middleware function.
/// Safe methods (GET, HEAD, OPTIONS) pass through and receive a token.
/// Unsafe methods (POST, PUT, DELETE, PATCH) require a valid token.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    switch (req.method) {
        .get, .head, .options => {
            if (ensureToken(req)) |token| {
                _ = res.header("X-CSRF-Token", token);
                log.debug("CSRF token set for {s} {s}", .{ @tagName(req.method), req.path });
            } else |_| {
                log.debug("CSRF token not available (no session) for {s} {s}", .{ @tagName(req.method), req.path });
            }
            next(req, res);
        },
        .post, .put, .delete, .patch => {
            const token = req.headers.get("X-CSRF-Token") orelse req.formValue("_csrf");
            if (token == null or !validateTokenForRequest(req, token.?)) {
                log.warn("CSRF validation failed for {s} {s}", .{ @tagName(req.method), req.path });
                _ = res.status(403);
                res.text("CSRF token missing or invalid") catch {};
                return;
            }
            log.debug("CSRF validated for {s} {s}", .{ @tagName(req.method), req.path });
            next(req, res);
        },
    }
}

/// Returns an HTML hidden input field with the CSRF token.
/// Use this to inject CSRF protection into forms:
///   {{ form_fields|safe }}
///   <input type="hidden" name="_csrf" value="{{ csrf_token }}">
pub fn formField() []const u8 {
    return "";
}

/// Return an owned hidden input field using the request/session token.
pub fn formFieldForRequest(gpa: std.mem.Allocator, req: *Request) ![]u8 {
    const token = try ensureToken(req);
    return std.fmt.allocPrint(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"{s}\">\n", .{token});
}

test {
    std.testing.refAllDecls(@This());
}
