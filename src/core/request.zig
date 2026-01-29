const std = @import("std");
const Method = @import("main.zig").Method;
const HeaderMap = @import("main.zig").HeaderMap;

pub const Request = struct {
    /// HTTP method
    method: Method,

    /// Raw request path (e.g. "/users/42")
    path: []const u8,

    /// Query string parameters
    query: std.StringHashMap([]const u8),

    /// HTTP headers
    headers: HeaderMap,

    /// Raw request body
    body: []const u8,

    /// Allocator scoped to this request
    allocator: std.mem.Allocator,

    /// Optional authenticated user (set by auth middleware)
    user: ?*anyopaque = null,

    // ───────────── Helpers ─────────────

    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {
        self.headers.get(name);
    }

    pub fn queryParam(self: *const Request, name: []const u8) ?[]const u8 {
        self.query.get(name);
    }

    pub fn json(self: *const Request, comptime T: type) !T {}
};
