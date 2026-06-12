/// zypher CLI — binary entry point.
const std = @import("std");
const zypher = @import("zypher");
const build_config = @import("build_config");

pub fn main(init: std.process.Init) !void {
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
