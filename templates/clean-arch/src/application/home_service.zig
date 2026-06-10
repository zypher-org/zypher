const domain = @import("../domain/greeting.zig");

pub fn homeGreeting() domain.Greeting {
    return .{
        .title = "{{project_name}}",
        .message = "Clean architecture scaffold is running.",
    };
}
