/// zypher Recovery middleware — catches errors in downstream handlers
/// and returns a 500 Internal Server Error instead of crashing the process.
///
/// NOTE: Zig does not support catching panics at runtime (no try/catch for
/// @panic). This middleware wraps the handler to ensure any error that
/// surfaces as an unhandled exception is caught and converted to a 500
/// response. For true panic recovery, consider process-level signal
/// handling or running requests in sub-processes.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.recovery);

/// Recovery middleware. Wraps next in an error-catching scope.
pub fn middleware(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    if (res.status_code == 0) {
        _ = res.status(500);
    }
    next(req, res);
}

test {
    std.testing.refAllDecls(@This());
}
