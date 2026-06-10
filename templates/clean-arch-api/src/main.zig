const std = @import("std");
const server = @import("infrastructure/server.zig");

pub fn main(init: std.process.Init) !void {
    try server.serve(init);
}

test "clean architecture api service returns resources" {
    const service = @import("application/resource_service.zig");
    try std.testing.expect(service.listResources().len > 0);
}
