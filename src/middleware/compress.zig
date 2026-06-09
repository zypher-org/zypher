/// zypher Compression middleware — gzip compression support.
///
/// When the client does not accept gzip, the response passes through
/// uncompressed (identity).
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.compress);

fn gzipBody(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    var out = try std.Io.Writer.Allocating.initCapacity(allocator, body.len + std.compress.flate.Container.gzip.size());
    defer out.deinit();

    const window = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(window);

    var gzip = try std.compress.flate.Compress.init(&out.writer, window, .gzip, .default);
    try gzip.writer.writeAll(body);
    try gzip.finish();
    return try out.toOwnedSlice();
}

/// Compression middleware function.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    // Call handler first to get the response
    next(req, res);

    // Check if client accepts gzip
    const accept = req.headers.get("Accept-Encoding") orelse return;
    if (std.mem.indexOf(u8, accept, "gzip") == null) {
        log.debug("client does not accept gzip, passing through", .{});
        return;
    }

    if (res.headers.get("Content-Encoding") != null) {
        log.debug("response already encoded, skipping gzip", .{});
        return;
    }

    const body = res.body orelse {
        log.debug("response has no body, skipping gzip", .{});
        return;
    };
    if (body.len == 0) {
        log.debug("response body empty, skipping gzip", .{});
        return;
    }

    const original_len = body.len;
    const compressed = gzipBody(res.allocator, body) catch |err| {
        log.warn("gzip compression failed: {}", .{err});
        return;
    };
    res.allocator.free(body);
    res.body = compressed;

    _ = res.header("Content-Encoding", "gzip");
    _ = res.header("Vary", "Accept-Encoding");
    log.info("response gzip-compressed: {d} -> {d} bytes", .{ original_len, compressed.len });
}

test {
    std.testing.refAllDecls(@This());
}
