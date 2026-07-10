const std = @import("std");
const zypher = @import("zypher");

test "spawn 5 io.async futures with defer cancel guards, zero leaks" {
    const io = std.testing.io;
    var f1 = io.async(struct {
        fn work() void {}
    }.work, .{});
    defer f1.cancel(io);
    var f2 = io.async(struct {
        fn work() void {}
    }.work, .{});
    defer f2.cancel(io);
    var f3 = io.async(struct {
        fn work() void {}
    }.work, .{});
    defer f3.cancel(io);
    var f4 = io.async(struct {
        fn work() void {}
    }.work, .{});
    defer f4.cancel(io);
    var f5 = io.async(struct {
        fn work() void {}
    }.work, .{});
    defer f5.cancel(io);

    _ = f1.await(io);
    _ = f2.await(io);
    _ = f3.await(io);
    _ = f4.await(io);
    _ = f5.await(io);
}
