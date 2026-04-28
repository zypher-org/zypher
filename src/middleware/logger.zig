/// zypher Logger middleware — logs method, path, status code, and duration.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.http);

/// Get a monotonic timestamp in nanoseconds.
/// Uses the Linux syscall directly to avoid libc dependency.
fn nanoNow() i128 {
    var ts: std.posix.timespec = undefined;
    const rc = std.os.linux.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
    if (rc != 0) return 0;
    return @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
}

/// The logger middleware function.
/// Logs: method, path, status code, and elapsed time in microseconds.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    const start = nanoNow();

    // Call next middleware/handler
    next(req, res);

    const end = nanoNow();
    const elapsed_ns = end - start;
    const elapsed_us: i64 = @intCast(@divTrunc(elapsed_ns, std.time.ns_per_us));

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
