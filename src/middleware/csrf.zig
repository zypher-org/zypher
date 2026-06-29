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
const util = @import("../util.zig");
const log = std.log.scoped(.csrf);

const session_key = "_csrf_token";

threadlocal var tl_io: ?std.Io = null;

pub fn setIo(io: std.Io) void {
    tl_io = io;
}

pub fn getIo() std.Io {
    return tl_io orelse @panic("csrf: no io set — call csrf.setIo(io) before using handler functions");
}

/// Return the request CSRF token, creating and storing one in the session.
pub fn ensureToken(io: std.Io, req: *Request) ![]const u8 {
    const user_ptr = req.user orelse return error.CsrfSessionUnavailable;
    // Safe: req.user is set by SessionMiddleware to *Session; exclusive writer invariant
    const session: *Session = @ptrCast(@alignCast(user_ptr));
    if (session.get(session_key)) |token| return token;

    var random: [32]u8 = undefined;
    util.randomBytes(io, &random);
    const hex = std.fmt.bytesToHex(random, .lower);
    try session.put(req.allocator, session_key, &hex);
    return session.get(session_key) orelse error.CsrfTokenUnavailable;
}

/// Return the request CSRF token using thread-local io (for handler contexts).
pub fn ensureTokenForRequest(req: *Request) ![]const u8 {
    return ensureToken(getIo(), req);
}

/// Validate a token against the request session.
pub fn validateTokenForRequest(req: *Request, token: []const u8) bool {
    if (req.user) |user_ptr| {
        // Safe: same req.user invariant as ensureToken()
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
pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    tl_io = io;
    switch (req.method) {
        .get, .head, .options => {
            if (ensureToken(io, req)) |token| {
                _ = res.header("X-CSRF-Token", token);
                log.debug("CSRF token set for {s} {s}", .{ @tagName(req.method), req.path });
            } else |_| {
                log.debug("CSRF token not available (no session) for {s} {s}", .{ @tagName(req.method), req.path });
            }
            next(io, req, res);
        },
        .post, .put, .delete, .patch => {
            const token = req.header("X-CSRF-Token") orelse req.formValue("_csrf");
            if (token == null or !validateTokenForRequest(req, token.?)) {
                log.warn("CSRF validation failed for {s} {s}", .{ @tagName(req.method), req.path });
                _ = res.status(403);
                res.text("CSRF token missing or invalid") catch {};
                return;
            }
            log.debug("CSRF validated for {s} {s}", .{ @tagName(req.method), req.path });
            next(io, req, res);
        },
    }
}

/// Returns an HTML hidden input field with the CSRF token from the request session.
pub fn formField(io: std.Io, req: *Request) ![]u8 {
    return formFieldForRequest(io, req.allocator, req);
}

/// Return an owned hidden input field using the request/session token.
pub fn formFieldForRequest(io: std.Io, gpa: std.mem.Allocator, req: *Request) ![]u8 {
    const token = try ensureToken(io, req);
    return std.fmt.allocPrint(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"{s}\">\n", .{token});
}

test {
    std.testing.refAllDecls(@This());
}
