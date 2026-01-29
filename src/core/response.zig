const std = @import("std");
const HeaderMap = @import("main.zig").HeaderMap;

pub const Response = struct {
    status: u16 = 200,
    headers: HeaderMap,
    body: []const u8 = "",

    allocator: std.mem.Allocator,

    // ───────────── Mutators ─────────────

    pub fn setStatus(self: *Response, code: u16) void {
        self.status = code;
    }

    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    // ───────────── Writers ─────────────

    pub fn text(self: *Response, content: []const u8) !void {}

    pub fn html(self: *Response, content: []const u8) !void {}

    pub fn json(self: *Response, value: anytype) !void {}

    pub fn redirect(self: *Response, location: []const u8) !void {}
};
