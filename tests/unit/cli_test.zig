const std = @import("std");
const cli = @import("zypher").cli_runner;

fn testInit() std.process.Init {
    return .{
        .minimal = undefined,
        .arena = undefined,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = undefined,
        .preopens = undefined,
    };
}

fn runCli(args: []const [:0]const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var err = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer err.deinit();

    const cmd = if (args.len > 1) args[1] else "help";
    try cli.dispatchInner(&out.writer, &err.writer, testInit(), cmd, args);

    try std.testing.expectEqual(@as(usize, 0), err.written().len);
    return try std.testing.allocator.dupe(u8, out.written());
}

test "cli: makemigrations detects added field and writes ALTER TABLE migration" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = std.Io.Dir.cwd();
    const schema_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/schema.zypher", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(schema_path);
    const state_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/schema.snapshot", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(state_path);
    const migrations_dir = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/migrations", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(migrations_dir);

    try cwd.writeFile(std.testing.io, .{ .sub_path = state_path, .data =
        \\table users
        \\field id integer primary
        \\field username text required unique
        \\
    });
    try cwd.writeFile(std.testing.io, .{ .sub_path = schema_path, .data =
        \\table users
        \\field id integer primary
        \\field username text required unique
        \\field email text unique
        \\
    });

    const args = [_][:0]const u8{
        "zypher",
        "makemigrations",
        "--schema",
        schema_path,
        "--state",
        state_path,
        "--dir",
        migrations_dir,
    };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "Created migration") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "add_email_to_users") != null);

    const migration_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/0001_add_email_to_users.sql", .{migrations_dir});
    defer std.testing.allocator.free(migration_path);
    const migration_sql = try cwd.readFileAlloc(std.testing.io, migration_path, std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(migration_sql);

    try std.testing.expect(std.mem.indexOf(u8, migration_sql, "ALTER TABLE users ADD COLUMN email TEXT UNIQUE;") != null);
}

test "cli: shell eval evaluates integer expressions" {
    const args = [_][:0]const u8{ "zypher", "shell", "--eval", "1 + 2 * 3" };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("7\n", output);
}

test "cli: shell session evaluates lines, reports help, and exits" {
    var input = std.Io.Reader.fixed("1 + 2\n:help\n:quit\n");
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var err = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer err.deinit();

    try cli.runShellSession(&input, &out.writer, &err.writer);

    try std.testing.expectEqual(@as(usize, 0), err.written().len);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "zypher shell") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "zypher> 3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Available commands") != null);
    try std.testing.expect(std.mem.endsWith(u8, out.written(), "bye\n"));
}
