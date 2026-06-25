/// zypher Recovery middleware — placeholder boundary for supervised recovery.
///
/// NOTE: Zig does not support catching panics at runtime through this
/// middleware signature. Handler and middleware functions currently return
/// void, so error-union recovery is not available here either. Use process
/// supervision for panic isolation.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;

/// Recovery middleware. Calls the next handler.
pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    next(io, req, res);
}

test {
    std.testing.refAllDecls(@This());
}
