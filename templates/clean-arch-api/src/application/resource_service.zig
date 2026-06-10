const domain = @import("../domain/resource.zig");

pub fn listResources() []const domain.Resource {
    return &.{.{ .id = 1, .name = "{{project_name}}" }};
}
