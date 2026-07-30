const std = @import("std");
const zypher = @import("zypher");
const Server = zypher.core.Server;
const Request = zypher.core.Request;
const Response = zypher.core.Response;

test "single-threaded: io.concurrent returns ConcurrencyUnavailable" {
    var backend = std.Io.Threaded.init_single_threaded;
    const io = backend.io();
    const fut = io.concurrent(struct {
        fn work() void {}
    }.work, .{});
    try std.testing.expectError(error.ConcurrencyUnavailable, fut);
}

test "single-threaded: server compiles with concurrent fallback path" {
    _ = Server;
}
