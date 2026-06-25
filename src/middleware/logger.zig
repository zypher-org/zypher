/// zypher Logger middleware — logs method, path, status code, and duration.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.http);

/// The logger middleware function.
/// Logs: method, path, status code, and elapsed time in microseconds.
pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    const start = std.Io.Timestamp.now(io, .awake);

    next(io, req, res);

    const end = std.Io.Timestamp.now(io, .awake);
    const elapsed = std.Io.Timestamp.durationTo(start, end);
    const elapsed_us: i64 = @intCast(@divTrunc(elapsed.nanoseconds, std.time.ns_per_us));

    log.info("{s} {s} → {d} ({d}µs)", .{
        @tagName(req.method),
        req.path,
        res.status_code,
        elapsed_us,
    });
}

test {
    std.testing.refAllDecls(@This());
}
