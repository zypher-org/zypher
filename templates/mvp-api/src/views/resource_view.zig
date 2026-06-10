const presenter = @import("../presenters/resource_presenter.zig");

pub const ApiResponse = struct {
    data: presenter.ResourceViewModel,
};

pub fn response(vm: presenter.ResourceViewModel) ApiResponse {
    return .{ .data = vm };
}
