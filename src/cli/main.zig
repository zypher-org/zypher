/// zypher CLI — binary entry point.
const std = @import("std");
const builtin = @import("builtin");
const zypher = @import("zypher");
const build_config = @import("build_config");

/// SIGINT support — installed once at process start so the library never calls sigaction.
const supports_posix_signals = builtin.os.tag != .windows and builtin.os.tag != .wasi;

var sigint_io: ?std.Io = null;

/// Posix SIGINT handler — only defined when on a POSIX platform.
const sigint = if (supports_posix_signals) struct {
    fn handler(
        sig: std.posix.SIG,
        info: *const std.posix.siginfo_t,
        context: ?*anyopaque,
    ) callconv(.c) void {
        _ = sig;
        _ = info;
        _ = context;
        if (zypher.cli_runner.sigint_app) |app| {
            if (sigint_io) |io| app.shutdown(io);
            zypher.cli_runner.sigint_app = null;
        }
    }

    var saved: std.posix.Sigaction = undefined;

    fn install(io: std.Io) void {
        sigint_io = io;
        const act: std.posix.Sigaction = .{
            .handler = .{ .sigaction = handler },
            .mask = std.posix.sigemptyset(),
            .flags = std.posix.SA.SIGINFO,
        };
        std.posix.sigaction(.INT, &act, &saved);
    }

    fn restore() void {
        std.posix.sigaction(.INT, &saved, null);
        sigint_io = null;
    }
} else struct {
    fn install(_: std.Io) void {}
    fn restore() void {}
};

pub fn main(init: std.process.Init) !void {
    sigint.install(init.io);
    defer sigint.restore();

    const args = try std.process.Args.toSlice(init.minimal.args, init.arena.allocator());
    try dispatch(init, args);
}

fn dispatch(init: std.process.Init, args: []const [:0]const u8) !void {
    const cmd = if (args.len > 1) args[1] else "help";

    const stdout = std.Io.File.stdout();
    var out_buf: [4096]u8 = undefined;
    var out_fw = stdout.writer(init.io, &out_buf);

    const stderr = std.Io.File.stderr();
    var err_buf: [4096]u8 = undefined;
    var err_fw = stderr.writer(init.io, &err_buf);

    try zypher.cli_runner.dispatchInner(&out_fw.interface, &err_fw.interface, init, cmd, args, build_config.version);

    try out_fw.flush();
    try err_fw.flush();
}
