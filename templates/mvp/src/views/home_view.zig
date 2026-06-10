const std = @import("std");
const presenter = @import("../presenters/home_presenter.zig");

pub fn render(allocator: std.mem.Allocator, vm: presenter.HomeViewModel) ![]u8 {
    return std.fmt.allocPrint(allocator, "<h1>{s}</h1><p>{s}</p>", .{ vm.title, vm.message });
}
