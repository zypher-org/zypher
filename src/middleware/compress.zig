/// zypher Compression middleware — gzip compression support.
///
/// When the client does not accept gzip, the response passes through
/// uncompressed (identity).
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.compress);

fn gzipBody(body: []const u8, writer: *std.Io.Writer) !void {
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var gzip = try std.compress.flate.Compress.init(writer, &window, .gzip, .default);
    try gzip.writer.writeAll(body);
    try gzip.finish();
}

/// Compression middleware function.
pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    // Call handler first to get the response
    next(io, req, res);

    // Check if client accepts gzip
    const accept = req.header("Accept-Encoding") orelse return;
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
    var alloc_writer = std.Io.Writer.Allocating.initCapacity(res.allocator, body.len + std.compress.flate.Container.gzip.size()) catch {
        log.warn("gzip compression failed: out of memory", .{});
        return;
    };
    defer alloc_writer.deinit();

    gzipBody(body, &alloc_writer.writer) catch |err| {
        log.warn("gzip compression failed: {}", .{err});
        return;
    };
    const compressed = alloc_writer.toOwnedSlice() catch |err| {
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
