const model = @import("../models/resource.zig");

pub const ResourceViewModel = struct {
    id: i64,
    label: []const u8,
};

pub fn present(resource: model.Resource) ResourceViewModel {
    return .{ .id = resource.id, .label = resource.name };
}
