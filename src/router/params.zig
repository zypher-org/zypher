/// zypher URL parameter extraction — zero-allocation param storage.
const std = @import("std");

pub const RouteParams = struct {
    /// Maximum number of parameters a single route can extract.
    pub const max_params = 16;

    names: [max_params][]const u8,
    values: [max_params][]const u8,
    len: usize = 0,
    allocator: std.mem.Allocator,

    /// Create an empty RouteParams.
    pub fn init(gpa: std.mem.Allocator) RouteParams {
        return .{
            .names = undefined,
            .values = undefined,
            .allocator = gpa,
        };
    }

    /// Free any allocated param values and reset.
    pub fn deinit(self: *RouteParams) void {
        self.len = 0;
    }

    /// Reset params for reuse without freeing the struct.
    pub fn reset(self: *RouteParams) void {
        self.len = 0;
    }

    /// Add a parameter. Overwrites if name already exists.
    pub fn put(self: *RouteParams, name: []const u8, value: []const u8) !void {
        // Check for existing key
        for (self.names[0..self.len], 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                self.values[i] = value;
                return;
            }
        }
        if (self.len >= max_params) return error.TooManyParams;
        self.names[self.len] = name;
        self.values[self.len] = value;
        self.len += 1;
    }

    /// Get a parameter value by name. Returns null if not found.
    pub fn get(self: *const RouteParams, name: []const u8) ?[]const u8 {
        for (self.names[0..self.len], 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return self.values[i];
        }
        return null;
    }

    /// Get a parameter value parsed as the given numeric type.
    /// Returns error.MissingParam if name not found.
    /// Returns parse error if value is not valid for the type.
    pub fn getAs(self: *const RouteParams, comptime T: type, name: []const u8) !T {
        const val = self.get(name) orelse return error.MissingParam;
        return std.fmt.parseInt(T, val, 10);
    }

    /// Number of parameters stored.
    pub fn count(self: *const RouteParams) usize {
        return self.len;
    }
};

test {
    std.testing.refAllDecls(@This());
}
