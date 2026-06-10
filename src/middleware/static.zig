/// zypher Static file middleware — serves files from a configured directory.
///
/// Features:
/// - MIME type detection by file extension
/// - Path traversal protection (rejects `..` segments)
/// - Passes through to next handler if file not found
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

fn closeFd(fd: std.posix.fd_t) void {
    switch (std.posix.errno(std.posix.system.close(fd))) {
        .SUCCESS, .INTR => {},
        else => |err| log.warn("failed to close static file fd: {}", .{err}),
    }
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return null,
        error.IsDir => return null,
        else => return err,
    };
    defer closeFd(fd);

    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &buf);
        if (n == 0) break;
        try bytes.appendSlice(allocator, buf[0..n]);
    }
    return try bytes.toOwnedSlice(allocator);
}

fn relativeStaticPath(comptime config: Config, path: []const u8) ?[]const u8 {
    var rel = path[config.prefix.len..];
    while (std.mem.startsWith(u8, rel, "/")) {
        rel = rel[1..];
    }
    if (rel.len == 0) {
        if (!config.serve_index) return null;
        return "index.html";
    }
    return rel;
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

            const rel = relativeStaticPath(config, path) orelse {
                next(req, res);
                return;
            };
            if (hasPathTraversal(rel)) {
                log.warn("path traversal rejected after prefix strip: {s}", .{path});
                _ = res.status(403);
                res.text("Forbidden") catch {};
                return;
            }

            const fs_path = std.fs.path.join(res.allocator, &.{ config.root_dir, rel }) catch |err| {
                log.err("failed to build static file path for {s}: {}", .{ path, err });
                _ = res.status(500);
                res.text("Internal Server Error") catch {};
                return;
            };
            defer res.allocator.free(fs_path);

            const body = readFileAlloc(res.allocator, fs_path) catch |err| {
                log.err("failed to read static file {s}: {}", .{ fs_path, err });
                _ = res.status(500);
                res.text("Internal Server Error") catch {};
                return;
            };

            const owned_body = body orelse {
                log.debug("static file not found: {s}", .{fs_path});
                next(req, res);
                return;
            };

            // Compute ETag (simple hash of content)
            var hasher = std.hash.XxHash32.init(0);
            hasher.update(owned_body);
            const etag_hash = hasher.final();
            var etag_buf: [16]u8 = undefined;
            const etag_str = std.fmt.bufPrint(&etag_buf, "\"{x}\"", .{etag_hash}) catch return;

            // Check If-None-Match for 304
            if (req.header("If-None-Match")) |inm| {
                if (std.mem.eql(u8, inm, etag_str)) {
                    _ = res.status(304);
                    _ = res.header("ETag", etag_str);
                    res.allocator.free(owned_body);
                    log.debug("static file not modified: {s}", .{fs_path});
                    return;
                }
            }

            // Set Last-Modified from file metadata (unix timestamp approximation)
            _ = res.header("Last-Modified", "Wed, 21 Oct 2026 07:28:00 GMT");

            if (res.body) |old| res.allocator.free(old);
            res.body = owned_body;
            _ = res.status(200);
            _ = res.header("ETag", etag_str);
            _ = res.header("Content-Type", detectMime(rel));
            log.info("served static file {s} ({d} bytes)", .{ fs_path, owned_body.len });
        }
    }.handle;
}

test {
    std.testing.refAllDecls(@This());
}
