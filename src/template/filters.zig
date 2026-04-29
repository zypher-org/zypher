/// zypher template filters — transform values in template expressions.
const std = @import("std");
const renderer = @import("renderer.zig");

const log = std.log.scoped(.template_filters);
const Value = renderer.Value;

pub const FilterResult = struct {
    value: Value,
    owned: bool,

    pub fn deinit(self: *FilterResult, gpa: std.mem.Allocator) void {
        if (self.owned) {
            switch (self.value) {
                .string => |s| gpa.free(@constCast(s)),
                else => {},
            }
        }
    }
};

pub const FilterFn = *const fn (std.mem.Allocator, Value) anyerror!FilterResult;

pub fn apply(gpa: std.mem.Allocator, name: []const u8, value: Value) !FilterResult {
    if (std.mem.eql(u8, name, "upper")) return filterUpper(gpa, value);
    if (std.mem.eql(u8, name, "lower")) return filterLower(gpa, value);
    if (std.mem.eql(u8, name, "capitalize")) return filterCapitalize(gpa, value);
    if (std.mem.eql(u8, name, "trim")) return filterTrim(gpa, value);
    if (std.mem.eql(u8, name, "length")) return filterLength(value);
    if (std.mem.eql(u8, name, "join")) return filterJoin(gpa, value, ", ");

    log.warn("unknown filter '{s}', passing through", .{name});
    return .{ .value = value, .owned = false };
}

pub fn applyWithArg(gpa: std.mem.Allocator, name: []const u8, value: Value, arg: []const u8) !FilterResult {
    if (std.mem.eql(u8, name, "join")) return filterJoin(gpa, value, arg);
    return apply(gpa, name, value);
}

pub fn applyDefault(gpa: std.mem.Allocator, value: Value, fallback: Value) !FilterResult {
    _ = gpa;
    if (value == .null_val) {
        return .{ .value = fallback, .owned = false };
    }
    return .{ .value = value, .owned = false };
}

fn filterUpper(gpa: std.mem.Allocator, value: Value) !FilterResult {
    switch (value) {
        .string => |s| {
            const buf = try gpa.alloc(u8, s.len);
            for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
            return .{ .value = .{ .string = buf }, .owned = true };
        },
        else => return .{ .value = value, .owned = false },
    }
}

fn filterLower(gpa: std.mem.Allocator, value: Value) !FilterResult {
    switch (value) {
        .string => |s| {
            const buf = try gpa.alloc(u8, s.len);
            for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
            return .{ .value = .{ .string = buf }, .owned = true };
        },
        else => return .{ .value = value, .owned = false },
    }
}

fn filterCapitalize(gpa: std.mem.Allocator, value: Value) !FilterResult {
    switch (value) {
        .string => |s| {
            if (s.len == 0) return .{ .value = value, .owned = false };
            const buf = try gpa.alloc(u8, s.len);
            @memcpy(buf, s);
            buf[0] = std.ascii.toUpper(buf[0]);
            return .{ .value = .{ .string = buf }, .owned = true };
        },
        else => return .{ .value = value, .owned = false },
    }
}

fn filterTrim(gpa: std.mem.Allocator, value: Value) !FilterResult {
    switch (value) {
        .string => |s| {
            const trimmed = std.mem.trim(u8, s, " \t\n\r");
            // Allocate a new slice for the trimmed result
            const buf = try gpa.alloc(u8, trimmed.len);
            @memcpy(buf, trimmed);
            return .{ .value = .{ .string = buf }, .owned = true };
        },
        else => return .{ .value = value, .owned = false },
    }
}

fn filterLength(value: Value) !FilterResult {
    switch (value) {
        .string => |s| return .{ .value = .{ .int = @as(i64, @intCast(s.len)) }, .owned = false },
        .list => |items| return .{ .value = .{ .int = @as(i64, @intCast(items.len)) }, .owned = false },
        else => return .{ .value = value, .owned = false },
    }
}

fn filterJoin(gpa: std.mem.Allocator, value: Value, sep: []const u8) !FilterResult {
    switch (value) {
        .list => |items| {
            var buf = std.ArrayList(u8).empty;
            defer buf.deinit(gpa);
            for (items, 0..) |item, i| {
                if (i > 0) try buf.appendSlice(gpa, sep);
                switch (item) {
                    .string => |s| try buf.appendSlice(gpa, s),
                    else => try buf.appendSlice(gpa, "?"),
                }
            }
            const result = try buf.toOwnedSlice(gpa);
            return .{ .value = .{ .string = result }, .owned = true };
        },
        else => return .{ .value = value, .owned = false },
    }
}

test {
    std.testing.refAllDecls(@This());
}
