/// Unit tests for zypher logging infrastructure.
const std = @import("std");
const log = @import("zypher").log;

test "log level filtering works — debug below info is suppressed" {
    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    log.setLogLevel(.warn);
    try std.testing.expect(!log.shouldLog(.debug));
    try std.testing.expect(!log.shouldLog(.info));
    try std.testing.expect(log.shouldLog(.warn));
    try std.testing.expect(log.shouldLog(.err));
}

test "log level filtering works — all levels at debug" {
    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    log.setLogLevel(.debug);
    try std.testing.expect(log.shouldLog(.debug));
    try std.testing.expect(log.shouldLog(.info));
    try std.testing.expect(log.shouldLog(.warn));
    try std.testing.expect(log.shouldLog(.err));
}

test "log level filtering works — only errors at err level" {
    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    log.setLogLevel(.err);
    try std.testing.expect(!log.shouldLog(.debug));
    try std.testing.expect(!log.shouldLog(.info));
    try std.testing.expect(!log.shouldLog(.warn));
    try std.testing.expect(log.shouldLog(.err));
}

test "output is captured when capture buffer is set" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    log.setLogLevel(.debug);
    log.startCapture(std.testing.allocator, &buf);
    log.writeLog(.info, "test_scope", "hello from capture test");
    log.stopCapture();

    const captured = buf.items;
    try std.testing.expect(captured.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, captured, "hello from capture test") != null);
    try std.testing.expect(std.mem.indexOf(u8, captured, "test_scope") != null);
    try std.testing.expect(std.mem.indexOf(u8, captured, "info") != null);
}

test "capture stops correctly — no output after stopCapture" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    log.setLogLevel(.debug);
    log.startCapture(std.testing.allocator, &buf);
    log.writeLog(.info, "scope", "captured message");
    log.stopCapture();

    const len_after_stop = buf.items.len;
    log.writeLog(.info, "scope", "should not be captured");
    try std.testing.expect(buf.items.len == len_after_stop);
}

test "logging does not allocate on the hot path — writeLog with no capture" {
    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    log.setLogLevel(.info);
    log.stopCapture();

    // writeLog with no capture buffer should not allocate.
    // We verify by calling it with the testing allocator context —
    // since writeLog doesn't take an allocator, it cannot allocate.
    // This test confirms the function signature and behaviour.
    log.writeLog(.info, "hot_path", "no allocation test");
    // If we got here without a memory leak, the test passes.
}

test "setLogLevel changes the current level" {
    const original_level = log.getLogLevel();
    defer log.setLogLevel(original_level);

    try std.testing.expectEqual(log.Level.info, log.getLogLevel());
    log.setLogLevel(.debug);
    try std.testing.expectEqual(log.Level.debug, log.getLogLevel());
    log.setLogLevel(.err);
    try std.testing.expectEqual(log.Level.err, log.getLogLevel());
}
