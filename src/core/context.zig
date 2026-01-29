const std = @import("std");
const Request = @import("request.zig").Request;

pub const Context = struct {
    req: *const Request,
    allocator: std.mem.Allocator,
};
