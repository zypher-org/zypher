const std = @import("std");

var single_backend: std.Io.Threaded = undefined;
var threaded_backend: std.Io.Threaded = undefined;
var single_ready = false;
var threaded_ready = false;

/// Returns a single-threaded `std.Io` suitable for unit tests.
/// Fully synchronous — no thread pool, no background workers.
pub fn testIo() std.Io {
    if (!single_ready) {
        single_backend = std.Io.Threaded.init(std.testing.allocator, .{});
        single_ready = true;
    }
    return single_backend.io();
}

/// Returns a multi-threaded `std.Io` backed by a small thread pool,
/// intended for integration and end-to-end tests.
pub fn testIoThreaded() std.Io {
    if (!threaded_ready) {
        threaded_backend = std.Io.Threaded.init(std.testing.allocator, .{
            .async_limit = .limited(4),
            .concurrent_limit = .limited(4),
        });
        threaded_ready = true;
    }
    return threaded_backend.io();
}

test "testIo returns a usable std.Io" {
    const io = testIo();
    _ = io;
}

test "testIoThreaded returns a usable std.Io" {
    const io = testIoThreaded();
    _ = io;
}
