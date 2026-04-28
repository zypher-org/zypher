/// Centralised log configuration helper for zypher.
/// Provides runtime log level control and writer redirection.
const std = @import("std");

const log = std.log.scoped(.zypher);

/// Supported log levels, matching std.log.Level.
pub const Level = enum(u2) {
    err = 0,
    warn = 1,
    info = 2,
    debug = 3,
};

/// Current global log level. Only messages at or below this level are emitted.
var current_level: Level = .info;

/// Optional custom writer for capturing log output (used in tests).
var custom_writer: ?*std.Io.Writer = null;

/// Allocator used for capture buffer operations.
var capture_gpa: std.mem.Allocator = undefined;

/// Buffer used when capturing log output to an ArrayList.
var capture_buffer: ?*std.ArrayList(u8) = null;

/// Set the runtime log level.
pub fn setLogLevel(level: Level) void {
    current_level = level;
    log.info("log level set to {s}", .{@tagName(level)});
}

/// Get the current log level.
pub fn getLogLevel() Level {
    return current_level;
}

/// Redirect log output to a custom writer.
/// Pass null to restore default behaviour.
pub fn setLogWriter(writer: ?*std.Io.Writer) void {
    custom_writer = writer;
    if (writer != null) {
        log.info("log writer redirected to custom writer", .{});
    } else {
        log.info("log writer restored to default", .{});
    }
}

/// Start capturing log output into the provided ArrayList.
/// Call stopCapture() when done.
pub fn startCapture(gpa: std.mem.Allocator, buffer: *std.ArrayList(u8)) void {
    capture_gpa = gpa;
    capture_buffer = buffer;
}

/// Stop capturing log output and restore previous writer.
pub fn stopCapture() void {
    capture_buffer = null;
}

/// Check if a given level would be emitted given the current config.
pub fn shouldLog(level: Level) bool {
    return @intFromEnum(level) <= @intFromEnum(current_level);
}

/// Write a log message to the configured output.
/// This is the low-level function used by the zypher log infrastructure.
pub fn writeLog(level: Level, scope: []const u8, msg: []const u8) void {
    if (!shouldLog(level)) return;

    // If we have a capture buffer active, write there
    if (capture_buffer) |buf| {
        buf.appendSlice(capture_gpa, "[") catch {};
        buf.appendSlice(capture_gpa, @tagName(level)) catch {};
        buf.appendSlice(capture_gpa, "] [") catch {};
        buf.appendSlice(capture_gpa, scope) catch {};
        buf.appendSlice(capture_gpa, "] ") catch {};
        buf.appendSlice(capture_gpa, msg) catch {};
        buf.appendSlice(capture_gpa, "\n") catch {};
        return;
    }

    // If we have a custom writer, use it
    if (custom_writer) |writer| {
        writer.print("[{s}] [{s}] {s}\n", .{ @tagName(level), scope, msg }) catch {};
        return;
    }

    // Default: use std.log
    switch (level) {
        .err => std.log.err("[{s}] {s}", .{ scope, msg }),
        .warn => std.log.warn("[{s}] {s}", .{ scope, msg }),
        .info => std.log.info("[{s}] {s}", .{ scope, msg }),
        .debug => std.log.debug("[{s}] {s}", .{ scope, msg }),
    }
}

test {
    std.testing.refAllDecls(@This());
}
