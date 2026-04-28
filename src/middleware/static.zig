/// zypher Static file middleware — serves files from a configured directory.
///
/// Features:
/// - MIME type detection by file extension
/// - Path traversal protection (rejects `..` segments)
/// - Passes through to next handler if file not found
///
/// v1 note: Actual file serving requires std.Io.Dir / std.Io.File which
/// need an Io instance. File serving will be fully implemented when the
/// middleware chain is wired into the server dispatch (which provides Io).
/// For now, path traversal protection and MIME detection are functional.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.static);

/// Configuration for static file middleware.
pub const Config = struct {
    /// Root directory to serve files from.
    root_dir: []const u8 = "./public",
    /// URL prefix to strip (e.g. "/static" → serves /static/foo.css as root/foo.css).
    prefix: []const u8 = "/",
    /// Whether to serve directory index files (index.html).
    serve_index: bool = true,
};

/// Detect MIME type from file extension.
pub fn detectMime(path: []const u8) []const u8 {
    // Find the last dot
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return "application/octet-stream";
    const ext = path[dot + 1 ..];

    // Common MIME types
    if (std.mem.eql(u8, ext, "html") or std.mem.eql(u8, ext, "htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, "css")) return "text/css";
    if (std.mem.eql(u8, ext, "js")) return "application/javascript";
    if (std.mem.eql(u8, ext, "json")) return "application/json";
    if (std.mem.eql(u8, ext, "png")) return "image/png";
    if (std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, "gif")) return "image/gif";
    if (std.mem.eql(u8, ext, "svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, "ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, "webp")) return "image/webp";
    if (std.mem.eql(u8, ext, "woff")) return "font/woff";
    if (std.mem.eql(u8, ext, "woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, "ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, "txt")) return "text/plain; charset=utf-8";
    if (std.mem.eql(u8, ext, "xml")) return "application/xml";
    if (std.mem.eql(u8, ext, "pdf")) return "application/pdf";
    if (std.mem.eql(u8, ext, "zip")) return "application/zip";
    return "application/octet-stream";
}

/// Check if a path contains traversal attempts (..).
fn hasPathTraversal(path: []const u8) bool {
    var iter = std.mem.splitSequence(u8, path, "/");
    while (iter.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}

/// Default static file middleware.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    middlewareWith(.{})(req, res, next);
}

/// Create a static file middleware with custom configuration.
pub fn middlewareWith(comptime config: Config) *const fn (*Request, *Response, *const fn (*Request, *Response) void) void {
    return struct {
        fn handle(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
            // Only serve GET requests
            if (req.method != .get) {
                next(req, res);
                return;
            }

            const path = req.path;

            // Reject path traversal
            if (hasPathTraversal(path)) {
                log.warn("path traversal rejected: {s}", .{path});
                _ = res.status(403);
                res.text("Forbidden") catch {};
                return;
            }

            // Check if path starts with prefix
            if (!std.mem.startsWith(u8, path, config.prefix)) {
                next(req, res);
                return;
            }

            // v1: path traversal protection is functional.
            // File serving via std.Io.Dir requires an Io instance,
            // which will be available when middleware is wired into
            // the server dispatch. For now, pass through.
            log.debug("static file path: {s} (serving deferred to Io layer)", .{path});
            next(req, res);
        }
    }.handle;
}

test {
    std.testing.refAllDecls(@This());
}
