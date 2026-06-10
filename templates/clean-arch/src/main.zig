const std = @import("std");
const server = @import("infrastructure/server.zig");

pub fn main(init: std.process.Init) !void {
    try server.serve(init);
}

test "clean architecture service returns a title" {
    const service = @import("application/home_service.zig");
    try std.testing.expect(service.homeGreeting().title.len > 0);
}
