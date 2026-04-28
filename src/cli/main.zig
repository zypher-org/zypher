/// zypher CLI entry point.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    var buf: [4096]u8 = undefined;
    var file_writer = stdout.writer(init.io, &buf);
    const w = &file_writer.interface;
    try w.print("zypher — Django-inspired web framework for Zig\n", .{});
    try w.print("Usage: zypher <command> [options]\n\n", .{});
    try w.print("Commands:\n", .{});
    try w.print("  new <name>         Create a new project\n", .{});
    try w.print("  runserver          Start the HTTP server\n", .{});
    try w.print("  migrate            Run pending migrations\n", .{});
    try w.print("  makemigrations     Generate migration files\n", .{});
    try w.print("  createsuperuser    Create a superuser account\n", .{});
    try w.print("  shell              Open interactive REPL\n", .{});
    try w.print("  help               Show this help message\n", .{});
    try file_writer.flush();
}
