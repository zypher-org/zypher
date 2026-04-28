/// zypher Compression middleware — gzip compression support.
///
/// For v1, this middleware checks `Accept-Encoding` and sets the
/// `Content-Encoding: gzip` header when the client supports it.
/// Actual gzip compression of the response body requires the `Io` runtime
/// and is deferred to the server's response writer layer (Phase 11).
///
/// When the client does not accept gzip, the response passes through
/// uncompressed (identity).
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.compress);

/// Compression middleware function.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    // Call handler first to get the response
    next(req, res);

    // Check if client accepts gzip
    const accept = req.headers.get("Accept-Encoding") orelse return;
    if (!std.mem.containsAtLeastScalar(u8, accept, 1, 'g') or !std.mem.containsAtLeastScalar(u8, accept, 1, 'z')) {
        log.debug("client does not accept gzip, passing through", .{});
        return;
    }

    // Mark response as gzip-encoded for the server writer layer
    _ = res.header("Content-Encoding", "gzip");
    log.info("response marked for gzip compression", .{});
}

test {
    std.testing.refAllDecls(@This());
}
