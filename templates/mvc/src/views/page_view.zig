const std = @import("std");
const page_model = @import("../models/page.zig");

pub fn renderHome(allocator: std.mem.Allocator, page: page_model.Page) ![]u8 {
    return std.fmt.allocPrint(allocator, "<h1>{s}</h1><p>{s}</p>", .{ page.title, page.body });
}
