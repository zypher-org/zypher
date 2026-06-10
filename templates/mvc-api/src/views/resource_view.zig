const model = @import("../models/resource.zig");

pub const ListResponse = struct {
    data: []const model.Resource,
};

pub fn listResponse() ListResponse {
    return .{ .data = model.list() };
}
