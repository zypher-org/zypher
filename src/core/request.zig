const std = @import("std");
const Method = @import("method.zig").Method;
const RouteParams = @import("../router/params.zig").RouteParams;
const log = std.log.scoped(.request);

pub const Request = struct {
    /// HTTP method
    method: Method,

    /// Raw request path (e.g. "/users/42")
    path: []const u8,

    /// Query string parameters
    query: std.StringHashMap([]const u8),

    /// HTTP headers
    headers: std.StringHashMap([]const u8),

    /// Raw request body
    body: []const u8,

    /// Route-extracted URL parameters (populated by Router.dispatch)
    params: RouteParams = .{ .names = undefined, .values = undefined, .len = 0, .allocator = undefined },

    /// Allocator scoped to this request
    allocator: std.mem.Allocator,

    /// Optional authenticated user (set by auth middleware)
    user: ?*anyopaque = null,

    // ───────────── Helpers ─────────────

    /// Case-insensitive header lookup.
    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {
        return getHeaderCI(&self.headers, name);
    }

    /// Query parameter lookup.
    pub fn queryParam(self: *const Request, name: []const u8) ?[]const u8 {
        return self.query.get(name);
    }

    /// Form value lookup (same storage as query for URL-encoded bodies).
    pub fn formValue(self: *const Request, name: []const u8) ?[]const u8 {
        return self.query.get(name);
    }

    /// Cookie lookup.
    pub fn cookie(self: *const Request, name: []const u8) ?[]const u8 {
        return self.query.get(name);
    }

    /// Free all owned memory.
    pub fn deinit(self: *Request) void {
        self.headers.deinit();
        self.query.deinit();
    }

    // ───────────── Static parsing helpers ─────────────

    /// Extract the path portion from a request target (before '?').
    pub fn parsePath(target: []const u8) []const u8 {
        if (std.mem.indexOfScalar(u8, target, '?')) |i| {
            return target[0..i];
        }
        return target;
    }

    /// Parse a query string into a StringHashMap. Caller owns the map.
    /// Use deinitQueryString to free all memory including decoded slices.
    pub fn parseQueryString(gpa: std.mem.Allocator, raw: []const u8) !std.StringHashMap([]const u8) {
        var map = std.StringHashMap([]const u8).init(gpa);
        if (raw.len == 0) return map;
        var it = std.mem.splitScalar(u8, raw, '&');
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
                const key = pair[0..i];
                const value = pair[i + 1 ..];
                const decoded_value = try decodeUrlEncoded(gpa, value);
                const decoded_key = try decodeUrlEncoded(gpa, key);
                try map.put(decoded_key, decoded_value);
            } else {
                const decoded = try decodeUrlEncoded(gpa, pair);
                try map.put(decoded, "");
            }
        }
        return map;
    }

    /// Free all memory from parseQueryString, including decoded key/value slices.
    pub fn deinitQueryString(map: *std.StringHashMap([]const u8), gpa: std.mem.Allocator) void {
        var it = map.iterator();
        while (it.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            if (entry.value_ptr.*.len > 0) {
                gpa.free(entry.value_ptr.*);
            }
        }
        map.deinit();
    }

    /// Parse application/x-www-form-urlencoded body into a map.
    pub fn parseFormUrlEncoded(gpa: std.mem.Allocator, body: []const u8) !std.StringHashMap([]const u8) {
        return parseQueryString(gpa, body);
    }

    /// Parse cookies from a Cookie header value.
    pub fn parseCookies(gpa: std.mem.Allocator, cookie_header: []const u8) !std.StringHashMap([]const u8) {
        var map = std.StringHashMap([]const u8).init(gpa);
        if (cookie_header.len == 0) return map;
        var it = std.mem.splitSequence(u8, cookie_header, "; ");
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
                const key = pair[0..i];
                const value = pair[i + 1 ..];
                try map.put(key, value);
            }
        }
        return map;
    }

    /// Case-insensitive header lookup from any header map.
    pub fn getHeaderCI(headers: *const std.StringHashMap([]const u8), name: []const u8) ?[]const u8 {
        var it = headers.iterator();
        while (it.next()) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, name)) {
                return entry.value_ptr.*;
            }
        }
        return null;
    }

    /// Validate body size against a maximum.
    pub fn validateBodySize(body_len: usize, max: usize) !void {
        if (body_len > max) return error.BodyTooLarge;
    }
};

/// Decode a URL-encoded string, replacing + with space and %XX with bytes.
fn decodeUrlEncoded(gpa: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '+') {
            try buf.append(gpa, ' ');
        } else if (raw[i] == '%' and i + 2 < raw.len) {
            const byte = std.fmt.parseInt(u8, raw[i + 1 .. i + 3], 16) catch 0;
            try buf.append(gpa, byte);
            i += 2;
        } else {
            try buf.append(gpa, raw[i]);
        }
    }
    return buf.toOwnedSlice(gpa);
}
