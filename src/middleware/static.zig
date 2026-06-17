/// zypher Static file middleware — serves files from a configured directory.
///
/// Features:
/// - MIME type detection by file extension (comprehensive: web, images, fonts,
///   video, audio, documents, archives, executables, scripts, etc.)
/// - Path traversal protection (rejects `..` segments)
/// - ETag caching with If-None-Match → 304
/// - Last-Modified with If-Modified-Since → 304
/// - HTTP Range requests (partial content, seeking in audio/video)
/// - HEAD requests (headers without body)
/// - Accept-Ranges signalling
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
    if (std.mem.eql(u8, ext, "sh") or std.mem.eql(u8, ext, "bash")) return "text/x-sh";
    if (std.mem.eql(u8, ext, "php")) return "text/x-php";
    if (std.mem.eql(u8, ext, "py")) return "text/x-python";
    if (std.mem.eql(u8, ext, "rb")) return "text/x-ruby";
    if (std.mem.eql(u8, ext, "pl")) return "text/x-perl";
    if (std.mem.eql(u8, ext, "java")) return "text/x-java-source";
    if (std.mem.eql(u8, ext, "go")) return "text/x-go";
    if (std.mem.eql(u8, ext, "rs")) return "text/x-rust";
    if (std.mem.eql(u8, ext, "c")) return "text/x-c";
    if (std.mem.eql(u8, ext, "cpp") or std.mem.eql(u8, ext, "cc") or std.mem.eql(u8, ext, "cxx")) return "text/x-c++";
    if (std.mem.eql(u8, ext, "hpp") or std.mem.eql(u8, ext, "hh") or std.mem.eql(u8, ext, "hxx") or std.mem.eql(u8, ext, "h")) return "text/x-c++";
    if (std.mem.eql(u8, ext, "tex")) return "application/x-latex";
    if (std.mem.eql(u8, ext, "ics")) return "text/calendar";
    if (std.mem.eql(u8, ext, "vcf")) return "text/vcard";
    if (std.mem.eql(u8, ext, "webmanifest")) return "application/manifest+json";

    // Images
    if (std.mem.eql(u8, ext, "png")) return "image/png";
    if (std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, "gif")) return "image/gif";
    if (std.mem.eql(u8, ext, "svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, "ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, "webp")) return "image/webp";
    if (std.mem.eql(u8, ext, "bmp")) return "image/bmp";
    if (std.mem.eql(u8, ext, "avif")) return "image/avif";
    if (std.mem.eql(u8, ext, "ppm")) return "image/x-portable-pixmap";
    if (std.mem.eql(u8, ext, "pgm")) return "image/x-portable-graymap";
    if (std.mem.eql(u8, ext, "pbm")) return "image/x-portable-bitmap";
    if (std.mem.eql(u8, ext, "pnm")) return "image/x-portable-anymap";
    if (std.mem.eql(u8, ext, "xcf")) return "image/x-xcf";
    if (std.mem.eql(u8, ext, "xpm")) return "image/x-xpixmap";
    if (std.mem.eql(u8, ext, "xwd")) return "image/x-xwindowdump";
    if (std.mem.eql(u8, ext, "tiff") or std.mem.eql(u8, ext, "tif")) return "image/tiff";
    if (std.mem.eql(u8, ext, "heif") or std.mem.eql(u8, ext, "heic")) return "image/heif";
    if (std.mem.eql(u8, ext, "eps")) return "image/x-eps";
    if (std.mem.eql(u8, ext, "dib")) return "image/x-ms-bmp";

    // Fonts
    if (std.mem.eql(u8, ext, "woff")) return "font/woff";
    if (std.mem.eql(u8, ext, "woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, "ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, "otf")) return "font/otf";
    if (std.mem.eql(u8, ext, "eot")) return "application/vnd.ms-fontobject";
    if (std.mem.eql(u8, ext, "ttc")) return "font/collection";

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
    if (std.mem.eql(u8, ext, "mpeg")) return "video/mpeg";
    if (std.mem.eql(u8, ext, "ts")) return "video/mp2t";
    if (std.mem.eql(u8, ext, "m2ts")) return "video/MP2T";

    // Audio
    if (std.mem.eql(u8, ext, "mp3")) return "audio/mpeg";
    if (std.mem.eql(u8, ext, "wav")) return "audio/wav";
    if (std.mem.eql(u8, ext, "ogg")) return "audio/ogg";
    if (std.mem.eql(u8, ext, "flac")) return "audio/flac";
    if (std.mem.eql(u8, ext, "aac")) return "audio/aac";
    if (std.mem.eql(u8, ext, "wma")) return "audio/x-ms-wma";
    if (std.mem.eql(u8, ext, "m4a")) return "audio/mp4";
    if (std.mem.eql(u8, ext, "opus")) return "audio/opus";
    if (std.mem.eql(u8, ext, "aiff") or std.mem.eql(u8, ext, "aif") or std.mem.eql(u8, ext, "aifc")) return "audio/x-aiff";
    if (std.mem.eql(u8, ext, "au") or std.mem.eql(u8, ext, "snd")) return "audio/basic";
    if (std.mem.eql(u8, ext, "m3u")) return "audio/x-mpegurl";
    if (std.mem.eql(u8, ext, "pls")) return "audio/x-scpls";
    if (std.mem.eql(u8, ext, "wax")) return "audio/x-ms-wax";
    if (std.mem.eql(u8, ext, "midi") or std.mem.eql(u8, ext, "mid") or std.mem.eql(u8, ext, "kar")) return "audio/midi";

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
    if (std.mem.eql(u8, ext, "torrent")) return "application/x-bittorrent";
    if (std.mem.eql(u8, ext, "cue")) return "application/x-cue";

    // Executables / binaries
    if (std.mem.eql(u8, ext, "exe") or std.mem.eql(u8, ext, "dll")) return "application/x-msdownload";
    if (std.mem.eql(u8, ext, "dylib")) return "application/x-mach-binary";
    if (std.mem.eql(u8, ext, "iso")) return "application/x-iso9660-image";
    if (std.mem.eql(u8, ext, "swf")) return "application/x-shockwave-flash";
    if (std.mem.eql(u8, ext, "deb")) return "application/x-deb";
    if (std.mem.eql(u8, ext, "rpm")) return "application/x-rpm";
    if (std.mem.eql(u8, ext, "mpkg")) return "application/vnd.apple.installer+xml";
    if (std.mem.eql(u8, ext, "msi")) return "application/vnd.microsoft.portable-executable";

    // Archives
    if (std.mem.eql(u8, ext, "zip")) return "application/zip";
    if (std.mem.eql(u8, ext, "tar")) return "application/x-tar";
    if (std.mem.eql(u8, ext, "gz")) return "application/gzip";
    if (std.mem.eql(u8, ext, "bz2")) return "application/x-bzip2";
    if (std.mem.eql(u8, ext, "7z")) return "application/x-7z-compressed";
    if (std.mem.eql(u8, ext, "rar")) return "application/vnd.rar";
    if (std.mem.eql(u8, ext, "lz")) return "application/x-lzip";
    if (std.mem.eql(u8, ext, "xz")) return "application/x-xz";
    if (std.mem.eql(u8, ext, "zst")) return "application/zstd";
    if (std.mem.eql(u8, ext, "Z")) return "application/x-compress";

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

/// Read a file into an allocated slice. Returns null if the file does not exist.
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

fn lseek(fd: std.posix.fd_t, offset: i64, whence: u32) i64 {
    if (@import("builtin").os.tag == .linux) {
        return @as(i64, @bitCast(std.os.linux.lseek(fd, offset, whence)));
    }
    return std.posix.system.lseek(fd, offset, whence);
}

/// Read a byte range from a file. The file must already be positioned
/// at the desired offset (via lseek). Returns up to `length` bytes.
fn readFileRange(allocator: std.mem.Allocator, fd: std.posix.fd_t, length: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, length);
    errdefer allocator.free(bytes);

    var total: usize = 0;
    while (total < length) {
        const n = try std.posix.read(fd, bytes[total..]);
        if (n == 0) break;
        total += n;
    }
    if (total < length) {
        return bytes[0..total];
    }
    return bytes;
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

    var st: std.posix.system.Stat = undefined;
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
///
/// Supports:
/// - GET  → serves file with ETag, Last-Modified, Accept-Ranges, optional Range
/// - HEAD → same headers as GET but no body
/// - Range → 206 Partial Content with Content-Range
/// - If-None-Match / If-Modified-Since → 304 Not Modified
/// - Path traversal → 403 Forbidden
/// - Missing file → passes through to next handler
pub fn middlewareWith(comptime config: Config) *const fn (*Request, *Response, *const fn (*Request, *Response) void) void {
    return struct {
        fn handle(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
            // Only serve GET and HEAD
            if (req.method != .get and req.method != .head) {
                next(req, res);
                return;
            }

            const is_head = req.method == .head;
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

            // Open file; if not found or is a directory, pass through
            const fd = std.posix.openat(std.posix.AT.FDCWD, fs_path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0) catch |err| switch (err) {
                error.FileNotFound, error.NotDir, error.IsDir => {
                    log.debug("static file not found: {s}", .{fs_path});
                    next(req, res);
                    return;
                },
                else => {
                    log.err("failed to open static file {s}: {}", .{ fs_path, err });
                    _ = res.status(500);
                    res.text("Internal Server Error") catch {};
                    return;
                },
            };
            defer closeFd(fd);

            // Get file size via seeking to end
            const file_size: u64 = @intCast(lseek(fd, 0, 2)); // SEEK_END = 2
            _ = lseek(fd, 0, 0); // SEEK_SET = 0 — seek back to beginning

            var last_modified_buf: [40]u8 = undefined;
            const last_modified = if (fileMtime(res.allocator, fs_path)) |mtime|
                httpDate(&last_modified_buf, mtime) catch ""
            else
                "";

            // Compute ETag (hash of full content — read into a temp buffer)
            const etag_str = etag: {
                var hasher = std.hash.XxHash32.init(0);
                var hash_buf: [8192]u8 = undefined;
                var total: usize = 0;
                while (true) {
                    const n = std.posix.read(fd, &hash_buf) catch break;
                    if (n == 0) break;
                    hasher.update(hash_buf[0..n]);
                    total += n;
                }
                // Seek back to start after computing hash
                _ = lseek(fd, 0, 0); // SEEK_SET = 0
                const etag_hash = hasher.final();
                var eb: [16]u8 = undefined;
                break :etag std.fmt.bufPrint(&eb, "\"{x}\"", .{etag_hash}) catch return;
            };

            // Check If-None-Match for 304
            if (req.header("If-None-Match")) |inm| {
                if (std.mem.eql(u8, inm, etag_str)) {
                    _ = res.status(304);
                    _ = res.header("ETag", etag_str);
                    if (last_modified.len > 0) _ = res.header("Last-Modified", last_modified);
                    _ = res.header("Accept-Ranges", "bytes");
                    log.debug("static file not modified: {s}", .{fs_path});
                    return;
                }
            }

            // Check If-Modified-Since for 304
            if (last_modified.len > 0) {
                if (req.header("If-Modified-Since")) |ims| {
                    if (std.mem.eql(u8, ims, last_modified)) {
                        _ = res.status(304);
                        _ = res.header("ETag", etag_str);
                        _ = res.header("Accept-Ranges", "bytes");
                        if (last_modified.len > 0) _ = res.header("Last-Modified", last_modified);
                        log.debug("static file not modified by Last-Modified: {s}", .{fs_path});
                        return;
                    }
                }
            }

            // Common headers
            _ = res.header("Accept-Ranges", "bytes");
            _ = res.header("ETag", etag_str);
            if (last_modified.len > 0) _ = res.header("Last-Modified", last_modified);
            _ = res.header("Content-Type", detectMime(rel));

            // Handle Range request
            if (req.range()) |range| {
                if (range.satisfy(file_size)) |satisfied| {
                    _ = res.status(206);

                    var cr_buf: [64]u8 = undefined;
                    const content_range = std.fmt.bufPrint(
                        &cr_buf,
                        "bytes {d}-{d}/{d}",
                        .{ satisfied.start, satisfied.end, file_size },
                    ) catch {
                        _ = res.status(500);
                        res.text("Internal Server Error") catch {};
                        return;
                    };
                    _ = res.header("Content-Range", content_range);

                    if (is_head) {
                        // HEAD: set Content-Length header, no body
                        var cl_buf: [16]u8 = undefined;
                        const len_str = std.fmt.bufPrint(&cl_buf, "{d}", .{satisfied.length}) catch return;
                        _ = res.header("Content-Length", len_str);
                    } else {
                        // Seek to range start and read the range
                        _ = lseek(fd, @intCast(satisfied.start), 0); // SEEK_SET = 0
                        const range_bytes = readFileRange(res.allocator, fd, @intCast(satisfied.length)) catch {
                            _ = res.status(500);
                            res.text("Internal Server Error") catch {};
                            return;
                        };
                        if (res.body) |old| res.allocator.free(old);
                        res.body = range_bytes;
                    }

                    log.info("served range {d}-{d}/{d} of {s}", .{ satisfied.start, satisfied.end, file_size, fs_path });
                    return;
                } else {
                    // Range not satisfiable
                    _ = res.status(416);
                    var cr_buf: [32]u8 = undefined;
                    const content_range = std.fmt.bufPrint(&cr_buf, "bytes */{d}", .{file_size}) catch return;
                    _ = res.header("Content-Range", content_range);
                    log.debug("range not satisfiable for {s}: range={any}, file_size={d}", .{ fs_path, range, file_size });
                    return;
                }
            }

            // Full file response (no Range header)
            if (is_head) {
                // HEAD: set Content-Length header, no body
                var len_buf: [16]u8 = undefined;
                const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{file_size}) catch return;
                _ = res.header("Content-Length", len_str);
                _ = res.status(200);
                log.info("head request for {s} ({d} bytes)", .{ fs_path, file_size });
                return;
            }

            // Read full file content
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
            if (res.body) |old| res.allocator.free(old);
            res.body = owned_body;
            _ = res.status(200);
            log.info("served static file {s} ({d} bytes)", .{ fs_path, owned_body.len });
        }
    }.handle;
}

test {
    std.testing.refAllDecls(@This());
}
