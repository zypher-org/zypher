/// CLI dispatch logic — testable separately from the binary entry point.
const std = @import("std");
const App = @import("../core/app.zig").App;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const sqlite = @import("../orm/sqlite.zig");
const migration = @import("../orm/migration.zig");
const password = @import("../auth/password.zig");
const log = std.log.scoped(.cli);

pub fn dispatchInner(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    cmd: []const u8,
    args: []const [:0]const u8,
) !void {
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help")) {
        try printHelp(out_writer);
    } else if (std.mem.eql(u8, cmd, "runserver")) {
        try cmdRunserver(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "createsuperuser")) {
        try cmdCreatesuperuser(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "migrate")) {
        try cmdMigrate(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "new")) {
        try cmdNew(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "makemigrations")) {
        try printStub(err_writer, cmd);
    } else if (std.mem.eql(u8, cmd, "shell")) {
        try printStub(err_writer, cmd);
    } else {
        try err_writer.print("zypher: unknown command '{s}'\n", .{cmd});
        std.process.exit(1);
    }
}

fn printHelp(w: *std.Io.Writer) !void {
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
}

fn printStub(w: *std.Io.Writer, cmd: []const u8) !void {
    try w.print("zypher {s}: not yet implemented\n", .{cmd});
    std.process.exit(1);
}

fn parseDbPath(args: []const [:0]const u8) ?[:0]const u8 {
    var i: usize = 2;
    while (i + 1 < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--db")) {
            return args[i + 1];
        }
    }
    return null;
}

// ── createsuperuser ───────────────────────────────────────────────────────

fn cmdCreatesuperuser(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const gpa = init.gpa;

    var username: ?[]const u8 = null;
    var plain_password: ?[]const u8 = null;
    var db_path: [:0]const u8 = "db.sqlite";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--username")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --username requires a value\n", .{});
                std.process.exit(1);
            }
            username = args[i];
        } else if (std.mem.eql(u8, args[i], "--password")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --password requires a value\n", .{});
                std.process.exit(1);
            }
            plain_password = args[i];
        } else if (std.mem.eql(u8, args[i], "--db")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --db requires a value\n", .{});
                std.process.exit(1);
            }
            db_path = args[i];
        } else {
            try err_writer.print("zypher: unknown option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }

    const uname = username orelse {
        try err_writer.print("zypher: --username is required\n", .{});
        std.process.exit(1);
    };
    const pwd = plain_password orelse {
        try err_writer.print("zypher: --password is required\n", .{});
        std.process.exit(1);
    };

    if (pwd.len < 8) {
        try err_writer.print("zypher: password must be at least 8 characters\n", .{});
        std.process.exit(1);
    }

    var db = sqlite.Db.open(gpa, db_path) catch {
        try err_writer.print("zypher: failed to open database '{s}'\n", .{db_path});
        std.process.exit(1);
    };
    defer db.close();

    db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  username TEXT NOT NULL UNIQUE,
        \\  password_hash TEXT NOT NULL,
        \\  role TEXT NOT NULL DEFAULT 'user',
        \\  is_active INTEGER NOT NULL DEFAULT 1
        \\)
    ) catch {
        try err_writer.print("zypher: failed to create users table\n", .{});
        std.process.exit(1);
    };

    const hash_str = password.hash(gpa, pwd) catch {
        try err_writer.print("zypher: failed to hash password\n", .{});
        std.process.exit(1);
    };
    defer gpa.free(hash_str);

    var stmt = db.prepare("INSERT INTO users (username, password_hash, role, is_active) VALUES (?, ?, 'admin', 1)") catch {
        try err_writer.print("zypher: failed to prepare insert\n", .{});
        std.process.exit(1);
    };
    defer stmt.finalize();

    stmt.bind(.{ .text = uname }, 1) catch {
        try err_writer.print("zypher: failed to bind username\n", .{});
        std.process.exit(1);
    };
    stmt.bind(.{ .text = hash_str }, 2) catch {
        try err_writer.print("zypher: failed to bind password\n", .{});
        std.process.exit(1);
    };

    _ = stmt.step() catch {
        try err_writer.print("zypher: failed to create user (username may already exist)\n", .{});
        std.process.exit(1);
    };

    const row_id = db.lastInsertRowId();
    log.info("created superuser '{s}' (id={d}, role=admin)", .{ uname, row_id });
    try out_writer.print("Superuser '{s}' created (id={d})\n", .{ uname, row_id });
}

// ── migrate ───────────────────────────────────────────────────────────────

fn cmdMigrate(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const gpa = init.gpa;
    var db_path: [:0]const u8 = "db.sqlite";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--db")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --db requires a value\n", .{});
                std.process.exit(1);
            }
            db_path = args[i];
        } else {
            try err_writer.print("zypher: unknown option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }

    var db = sqlite.Db.open(gpa, db_path) catch {
        try err_writer.print("zypher: failed to open database '{s}'\n", .{db_path});
        std.process.exit(1);
    };
    defer db.close();

    var runner = migration.MigrationRunner.init(&db);
    runner.ensureHistoryTable() catch {
        try err_writer.print("zypher: failed to create migration history table\n", .{});
        std.process.exit(1);
    };

    const count = runner.countApplied() catch 0;
    try out_writer.print("zypher: database '{s}' — {d} migration(s) applied\n", .{ db_path, count });

    if (count == 0) {
        try out_writer.print("zypher: no migrations found. Use zypher makemigrations first.\n", .{});
    } else {
        try out_writer.print("zypher: all migrations are up to date.\n", .{});
    }
}

// ── new (scaffold) ────────────────────────────────────────────────────────

fn cmdNew(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    if (args.len < 3) {
        try err_writer.print("zypher: new requires a project name\n", .{});
        std.process.exit(1);
    }
    const project_name = args[2];
    const io = init.io;

    if (project_name.len == 0) {
        try err_writer.print("zypher: project name cannot be empty\n", .{});
        std.process.exit(1);
    }
    for (project_name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
            try err_writer.print("zypher: invalid project name '{s}' — use only letters, numbers, _, -\n", .{project_name});
            std.process.exit(1);
        }
    }

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, project_name, .default_dir) catch {
        try err_writer.print("zypher: failed to create directory '{s}'\n", .{project_name});
        std.process.exit(1);
    };

    {
        const path = try std.fmt.allocPrint(init.gpa, "{s}/build.zig", .{project_name});
        defer init.gpa.free(path);
        cwd.writeFile(io, .{ .sub_path = path, .data =
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {
            \\    const target = b.standardTargetOptions(.{});
            \\    const optimize = b.standardOptimizeOption(.{});
            \\
            \\    const zypher_mod = b.dependency("zypher", .{
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }).module("zypher");
            \\
            \\    const exe = b.addExecutable(.{
            \\        .name = "{s}",
            \\        .root_module = b.createModule(.{
            \\            .root_source_file = b.path("src/main.zig"),
            \\            .target = target,
            \\            .optimize = optimize,
            \\            .imports = &.{.{ .name = "zypher", .module = zypher_mod }},
            \\        }),
            \\    });
            \\    b.installArtifact(exe);
            \\
            \\    const run_cmd = b.addRunArtifact(exe);
            \\    run_cmd.step.dependOn(b.getInstallStep());
            \\    run_cmd.addPassthruArgs();
            \\
            \\    const run_step = b.step("run", "Run the app");
            \\    run_step.dependOn(&run_cmd.step);
            \\}
            \\
        }) catch {
            try err_writer.print("zypher: failed to write build.zig\n", .{});
            std.process.exit(1);
        };
    }

    {
        const path = try std.fmt.allocPrint(init.gpa, "{s}/src", .{project_name});
        defer init.gpa.free(path);
        cwd.createDirPath(io, path) catch {};
    }
    {
        const path = try std.fmt.allocPrint(init.gpa, "{s}/templates", .{project_name});
        defer init.gpa.free(path);
        cwd.createDirPath(io, path) catch {};
    }
    {
        const path = try std.fmt.allocPrint(init.gpa, "{s}/tests", .{project_name});
        defer init.gpa.free(path);
        cwd.createDirPath(io, path) catch {};
    }
    {
        const path = try std.fmt.allocPrint(init.gpa, "{s}/src/main.zig", .{project_name});
        defer init.gpa.free(path);
        cwd.writeFile(io, .{ .sub_path = path, .data =
            \\const std = @import("std");
            \\const zypher = @import("zypher");
            \\
            \\pub fn main() !void {
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            \\    const alloc = gpa.allocator();
            \\    _ = alloc;
            \\    std.log.info("zypher app started", .{});
            \\}
            \\
        }) catch {
            try err_writer.print("zypher: failed to write src/main.zig\n", .{});
            std.process.exit(1);
        };
    }

    log.info("scaffolded project '{s}'", .{project_name});
    try out_writer.print("Created project '{s}'\n", .{project_name});
    try out_writer.print("  {s}/build.zig\n", .{project_name});
    try out_writer.print("  {s}/src/main.zig\n", .{project_name});
    try out_writer.print("  {s}/templates/\n", .{project_name});
    try out_writer.print("  {s}/tests/\n", .{project_name});
}

// ── runserver ─────────────────────────────────────────────────────────────

fn cmdRunserver(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const gpa = init.gpa;

    var port: u16 = 8080;
    var host: []const u8 = "127.0.0.1";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --port requires a value\n", .{});
                std.process.exit(1);
            }
            port = std.fmt.parseInt(u16, args[i], 10) catch {
                try err_writer.print("zypher: invalid port '{s}'\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, args[i], "--host")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --host requires a value\n", .{});
                std.process.exit(1);
            }
            host = args[i];
        } else {
            try err_writer.print("zypher: unknown option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }

    try out_writer.print("Starting zypher server at http://{s}:{d}/\n", .{ host, port });

    var app = App.init(gpa, .{ .host = host, .port = port });
    defer app.deinit();

    app.handler_fn = struct {
        fn handle(req: *Request, res: *Response) void {
            _ = req;
            res.text("zypher server is running") catch {};
        }
    }.handle;

    try app.listenAndServe(init.io);
}
