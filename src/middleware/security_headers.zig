/// zypher security headers middleware — sets standard security-related HTTP headers.
///
/// Adds the following headers to every response:
/// - X-Content-Type-Options: nosniff
/// - X-Frame-Options: DENY
/// - Referrer-Policy: strict-origin-when-cross-origin
/// - X-XSS-Protection: 0 (deprecated but harmless)
///
/// Configuration is available to selectively enable/disable headers.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.security_headers);

pub const Options = struct {
    x_content_type_options: bool = true,
    x_frame_options: bool = true,
    referrer_policy: bool = true,
    x_xss_protection: bool = true,
    content_security_policy: bool = false,
    strict_transport_security: bool = false,
    custom_headers: []const []const u8 = &.{},
};

threadlocal var config: Options = .{};

pub fn configure(opts: Options) void {
    config = opts;
}

pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    if (config.x_content_type_options) {
        _ = res.header("X-Content-Type-Options", "nosniff");
    }
    if (config.x_frame_options) {
        _ = res.header("X-Frame-Options", "DENY");
    }
    if (config.referrer_policy) {
        _ = res.header("Referrer-Policy", "strict-origin-when-cross-origin");
    }
    if (config.x_xss_protection) {
        _ = res.header("X-XSS-Protection", "0");
    }
    if (config.content_security_policy) {
        _ = res.header("Content-Security-Policy", "default-src 'self'");
    }
    if (config.strict_transport_security) {
        _ = res.header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    }

    var ci: usize = 0;
    while (ci < config.custom_headers.len) : (ci += 2) {
        if (ci + 1 < config.custom_headers.len) {
            _ = res.header(config.custom_headers[ci], config.custom_headers[ci + 1]);
        }
    }

    log.debug("security headers set for {s} {s}", .{ @tagName(req.method), req.path });
    next(io, req, res);
}

test {
    std.testing.refAllDecls(@This());
}
