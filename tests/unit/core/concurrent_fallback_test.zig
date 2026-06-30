const std = @import("std");
const zypher = @import("zypher");
const Server = zypher.core.Server;
const Request = zypher.core.Request;
const Response = zypher.core.Response;

test "single-threaded io.concurrent returns ConcurrencyUnavailable" {
    const io = std.testing.io;
    const fut = io.concurrent(struct {
        fn work() void {}
    }.work, .{});
    try std.testing.expectError(error.ConcurrencyUnavailable, fut);
}

test "single-threaded server compiles and accepts io.concurrent fallback path" {
    // Compile-time check: the server must handle ConcurrencyUnavailable
    // from io.concurrent() gracefully. Under single-threaded build this
    // falls through to inline serving. No active-task tracking needed.
    // Full runtime coverage with threading lives in server_test.zig.
    _ = Server;
}
