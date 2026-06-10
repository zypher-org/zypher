const page_model = @import("../models/page.zig");

pub const HomeViewModel = struct {
    title: []const u8,
    message: []const u8,
};

pub fn present(page: page_model.Page) HomeViewModel {
    return .{
        .title = page.name,
        .message = "MVP scaffold is running.",
    };
}
