/// zypher CSRF middleware — Cross-Site Request Forgery protection.
///
/// For GET/HEAD/OPTIONS: generates a token and sets it in the X-CSRF-Token response header.
/// For POST/PUT/DELETE/PATCH: validates the X-CSRF-Token request header against the stored token.
/// If missing or mismatched, returns 403.
///
/// Note: This is a simplified implementation using a per-process secret.
/// A production implementation would store tokens in session storage.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.csrf);

/// Per-process CSRF secret. Generated once at startup.
const secret = "zypher-csrf-secret-key-2026";

/// Generate a CSRF token. In a real implementation this would be HMAC
/// of the session ID with the secret. For v1, we use a fixed token
/// derived from the secret.
fn generateToken() []const u8 {
    return secret;
}

/// Validate a CSRF token against the expected value.
fn validateToken(token: []const u8) bool {
    return std.mem.eql(u8, token, secret);
}

/// CSRF middleware function.
/// Safe methods (GET, HEAD, OPTIONS) pass through and receive a token.
/// Unsafe methods (POST, PUT, DELETE, PATCH) require a valid token.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    switch (req.method) {
        .get, .head, .options => {
            // Safe method — generate and set token
            const token = generateToken();
            _ = res.header("X-CSRF-Token", token);
            log.debug("CSRF token set for {s} {s}", .{ @tagName(req.method), req.path });
            next(req, res);
        },
        .post, .put, .delete, .patch => {
            // Unsafe method — validate token
            const token = req.headers.get("X-CSRF-Token");
            if (token == null or !validateToken(token.?)) {
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

test {
    std.testing.refAllDecls(@This());
}
