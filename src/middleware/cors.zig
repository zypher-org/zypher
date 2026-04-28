/// zypher CORS middleware — Cross-Origin Resource Sharing.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.cors);

/// Configuration for CORS middleware.
pub const Config = struct {
    /// Origins allowed. null = allow all (reflect request Origin).
    /// Empty slice = block all (no CORS headers).
    allowed_origins: ?[]const []const u8 = null,
    /// Methods allowed for preflight responses.
    allowed_methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
    /// Headers allowed for preflight responses.
    allowed_headers: []const u8 = "Content-Type, Authorization, X-CSRF-Token",
    /// Max-Age for preflight cache (seconds).
    max_age: []const u8 = "86400",
    /// Whether to allow credentials (cookies, auth headers).
    allow_credentials: bool = false,
};

/// Default CORS middleware — allows all origins.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    middlewareWith(.{})(req, res, next);
}

/// Create a CORS middleware with custom configuration.
pub fn middlewareWith(comptime config: Config) *const fn (*Request, *Response, *const fn (*Request, *Response) void) void {
    return struct {
        fn handle(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
            const origin = req.headers.get("Origin");

            // No Origin header — not a CORS request, pass through
            if (origin == null) {
                next(req, res);
                return;
            }

            // Check if origin is allowed
            if (!isAllowed(config, origin.?)) {
                log.warn("CORS blocked origin: {s}", .{origin.?});
                _ = res.status(403);
                res.text("CORS origin not allowed") catch {};
                return;
            }

            // Handle preflight (OPTIONS) request
            if (req.method == .options) {
                log.info("CORS preflight: {s} {s}", .{ origin.?, req.path });
                _ = res.status(204);
                _ = res.header("Access-Control-Allow-Origin", origin.?);
                _ = res.header("Access-Control-Allow-Methods", config.allowed_methods);
                _ = res.header("Access-Control-Allow-Headers", config.allowed_headers);
                _ = res.header("Access-Control-Max-Age", config.max_age);
                if (config.allow_credentials) {
                    _ = res.header("Access-Control-Allow-Credentials", "true");
                }
                return;
            }

            // Normal CORS request — add Allow-Origin and pass through
            _ = res.header("Access-Control-Allow-Origin", origin.?);
            if (config.allow_credentials) {
                _ = res.header("Access-Control-Allow-Credentials", "true");
            }
            log.debug("CORS allowed: {s}", .{origin.?});
            next(req, res);
        }
    }.handle;
}

/// Check if an origin is allowed by the configuration.
fn isAllowed(comptime config: Config, origin: []const u8) bool {
    // null allowed_origins = allow all
    if (config.allowed_origins == null) return true;
    // Empty allowed_origins = block all
    if (config.allowed_origins.?.len == 0) return false;
    // Check against allowlist
    for (config.allowed_origins.?) |allowed| {
        if (std.mem.eql(u8, origin, allowed)) return true;
    }
    return false;
}

test {
    std.testing.refAllDecls(@This());
}
