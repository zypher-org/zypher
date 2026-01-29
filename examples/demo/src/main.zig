const std = @import("std");
const zypher = @import("zypher");
const router = @import("router");

pub fn main(init: std.process.Init) !void {
    var app = zypher.App.init(init.gpa, init.io);
    defer app.deinit();

    try app.run(.{ .port = 8080, .router = router });
}
