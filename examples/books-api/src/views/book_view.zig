const std = @import("std");
const book = @import("../models/book.zig");

fn writeJsonString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, c),
        }
    }
    try out.append(allocator, '"');
}

fn writeBook(out: *std.ArrayList(u8), allocator: std.mem.Allocator, row: book.BookRow) !void {
    try out.print(allocator, "{{\"id\":{d},\"title\":", .{row[0]});
    try writeJsonString(out, allocator, row[1]);
    try out.appendSlice(allocator, ",\"author\":");
    try writeJsonString(out, allocator, row[2]);
    try out.print(allocator, ",\"year\":{d},\"created_at\":{d}}}", .{ row[3], row[4] });
}

pub fn bookJson(allocator: std.mem.Allocator, row: book.BookRow) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"data\":");
    try writeBook(&out, allocator, row);
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

pub fn listJson(allocator: std.mem.Allocator, rows: []const book.BookRow) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"data\":[");
    for (rows, 0..) |row, i| {
        if (i > 0) try out.append(allocator, ',');
        try writeBook(&out, allocator, row);
    }
    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

pub fn messageJson(allocator: std.mem.Allocator, message: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"message\":");
    try writeJsonString(&out, allocator, message);
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}
