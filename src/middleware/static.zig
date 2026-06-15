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

    // Text / web
    if (std.mem.eql(u8, ext, "html") or std.mem.eql(u8, ext, "htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, "css")) return "text/css";
    if (std.mem.eql(u8, ext, "js") or std.mem.eql(u8, ext, "mjs") or std.mem.eql(u8, ext, "cjs") or std.mem.eql(u8, ext, "jsx")) return "application/javascript";
    if (std.mem.eql(u8, ext, "json")) return "application/json";
    if (std.mem.eql(u8, ext, "map")) return "application/json";
    if (std.mem.eql(u8, ext, "xml")) return "application/xml";
    if (std.mem.eql(u8, ext, "yaml") or std.mem.eql(u8, ext, "yml")) return "application/yaml";
    if (std.mem.eql(u8, ext, "toml")) return "application/toml";
    if (std.mem.eql(u8, ext, "txt")) return "text/plain; charset=utf-8";
    if (std.mem.eql(u8, ext, "csv")) return "text/csv; charset=utf-8";
    if (std.mem.eql(u8, ext, "ts") or std.mem.eql(u8, ext, "tsx")) return "application/typescript";
    if (std.mem.eql(u8, ext, "rss")) return "application/rss+xml";
    if (std.mem.eql(u8, ext, "atom")) return "application/atom+xml";

    // Images
    if (std.mem.eql(u8, ext, "png")) return "image/png";
    if (std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, "gif")) return "image/gif";
    if (std.mem.eql(u8, ext, "svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, "ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, "webp")) return "image/webp";
    if (std.mem.eql(u8, ext, "bmp")) return "image/bmp";
    if (std.mem.eql(u8, ext, "avif")) return "image/avif";

    // Fonts
    if (std.mem.eql(u8, ext, "woff")) return "font/woff";
    if (std.mem.eql(u8, ext, "woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, "ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, "otf")) return "font/otf";
    if (std.mem.eql(u8, ext, "eot")) return "application/vnd.ms-fontobject";

    // Video
    if (std.mem.eql(u8, ext, "mp4")) return "video/mp4";
    if (std.mem.eql(u8, ext, "webm")) return "video/webm";
    if (std.mem.eql(u8, ext, "mkv")) return "video/x-matroska";
    if (std.mem.eql(u8, ext, "avi")) return "video/x-msvideo";
    if (std.mem.eql(u8, ext, "mov")) return "video/quicktime";
    if (std.mem.eql(u8, ext, "wmv")) return "video/x-ms-wmv";
    if (std.mem.eql(u8, ext, "flv")) return "video/x-flv";
    if (std.mem.eql(u8, ext, "m4v")) return "video/x-m4v";
    if (std.mem.eql(u8, ext, "3gp")) return "video/3gpp";
    if (std.mem.eql(u8, ext, "ogv")) return "video/ogg";

    // Audio
    if (std.mem.eql(u8, ext, "mp3")) return "audio/mpeg";
    if (std.mem.eql(u8, ext, "wav")) return "audio/wav";
    if (std.mem.eql(u8, ext, "ogg")) return "audio/ogg";
    if (std.mem.eql(u8, ext, "flac")) return "audio/flac";
    if (std.mem.eql(u8, ext, "aac")) return "audio/aac";
    if (std.mem.eql(u8, ext, "wma")) return "audio/x-ms-wma";
    if (std.mem.eql(u8, ext, "m4a")) return "audio/mp4";
    if (std.mem.eql(u8, ext, "opus")) return "audio/opus";

    // Documents
    if (std.mem.eql(u8, ext, "pdf")) return "application/pdf";
    if (std.mem.eql(u8, ext, "doc")) return "application/msword";
    if (std.mem.eql(u8, ext, "docx")) return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    if (std.mem.eql(u8, ext, "xls")) return "application/vnd.ms-excel";
    if (std.mem.eql(u8, ext, "xlsx")) return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    if (std.mem.eql(u8, ext, "ppt")) return "application/vnd.ms-powerpoint";
    if (std.mem.eql(u8, ext, "pptx")) return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    if (std.mem.eql(u8, ext, "odt")) return "application/vnd.oasis.opendocument.text";
    if (std.mem.eql(u8, ext, "ods")) return "application/vnd.oasis.opendocument.spreadsheet";
    if (std.mem.eql(u8, ext, "odp")) return "application/vnd.oasis.opendocument.presentation";
    if (std.mem.eql(u8, ext, "rtf")) return "application/rtf";
    if (std.mem.eql(u8, ext, "epub")) return "application/epub+zip";

    // Archives
    if (std.mem.eql(u8, ext, "zip")) return "application/zip";
    if (std.mem.eql(u8, ext, "tar")) return "application/x-tar";
    if (std.mem.eql(u8, ext, "gz")) return "application/gzip";
    if (std.mem.eql(u8, ext, "bz2")) return "application/x-bzip2";
    if (std.mem.eql(u8, ext, "7z")) return "application/x-7z-compressed";
    if (std.mem.eql(u8, ext, "rar")) return "application/vnd.rar";

    // WASM
    if (std.mem.eql(u8, ext, "wasm")) return "application/wasm";

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

fn httpDate(buf: []u8, timestamp: std.Io.Timestamp) ![]const u8 {
    const secs = timestamp.toSeconds();
    if (secs < 0) return error.InvalidTimestamp;
    const unix_secs: u64 = @intCast(secs);
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = unix_secs };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const weekdays = [_][]const u8{ "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed" };
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    const weekday = weekdays[epoch_day.day % 7];
    const month = months[@intFromEnum(month_day.month) - 1];

    return std.fmt.bufPrint(
        buf,
        "{s}, {d:0>2} {s} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2} GMT",
        .{
            weekday,
            month_day.day_index + 1,
            month,
            year_day.year,
            day_secs.getHoursIntoDay(),
            day_secs.getMinutesIntoHour(),
            day_secs.getSecondsIntoMinute(),
        },
    );
}

fn fileMtime(gpa: std.mem.Allocator, path: []const u8) ?std.Io.Timestamp {
    const path_z = gpa.dupeSentinel(u8, path, 0) catch return null;
    defer gpa.free(path_z);

    if (@import("builtin").os.tag == .linux) {
        var stx: std.os.linux.Statx = undefined;
        const rc = std.os.linux.statx(
            std.posix.AT.FDCWD,
            path_z.ptr,
            std.os.linux.AT.NO_AUTOMOUNT,
            .{ .MTIME = true },
            &stx,
        );
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                const nanos = @as(i96, @intCast(stx.mtime.sec)) * std.time.ns_per_s + @as(i96, @intCast(stx.mtime.nsec));
                return std.Io.Timestamp.fromNanoseconds(nanos);
            },
            else => return null,
        }
    }

    var st: std.posix.Stat = undefined;
    _ = std.posix.system.stat(path_z.ptr, &st);
    const nanos = @as(i96, @intCast(st.mtim.sec)) * std.time.ns_per_s;
    return std.Io.Timestamp.fromNanoseconds(nanos);
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
            errdefer res.allocator.free(owned_body);

            var last_modified_buf: [40]u8 = undefined;
            const last_modified = if (fileMtime(res.allocator, fs_path)) |mtime|
                httpDate(&last_modified_buf, mtime) catch ""
            else
                "";

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
                    if (last_modified.len > 0) _ = res.header("Last-Modified", last_modified);
                    res.allocator.free(owned_body);
                    log.debug("static file not modified: {s}", .{fs_path});
                    return;
                }
            }

            if (last_modified.len > 0) {
                _ = res.header("Last-Modified", last_modified);
                if (req.header("If-Modified-Since")) |ims| {
                    if (std.mem.eql(u8, ims, last_modified)) {
                        _ = res.status(304);
                        _ = res.header("ETag", etag_str);
                        res.allocator.free(owned_body);
                        log.debug("static file not modified by Last-Modified: {s}", .{fs_path});
                        return;
                    }
                }
            }

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
