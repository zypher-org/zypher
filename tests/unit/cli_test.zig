const std = @import("std");
const cli = @import("zypher").cli_runner;
const log = @import("zypher").log;
const password = @import("zypher").auth.password;
const App = @import("zypher").core.App;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const sqlite = @import("zypher").orm.sqlite;

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

test "cli: new creates expected project skeleton" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const project_name = try std.fmt.allocPrintSentinel(std.testing.allocator, "zypher_cli_new_{s}", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(project_name);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, project_name) catch {};

    const args = [_][:0]const u8{ "zypher", "new", project_name };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    const cwd = std.Io.Dir.cwd();
    var root = try cwd.openDir(std.testing.io, project_name, .{});
    defer root.close(std.testing.io);
    var src = try root.openDir(std.testing.io, "src", .{});
    defer src.close(std.testing.io);

    const build_zig = try root.readFileAlloc(std.testing.io, "build.zig", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(build_zig);
    const main_zig = try src.readFileAlloc(std.testing.io, "main.zig", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(main_zig);

    try std.testing.expect(std.mem.indexOf(u8, output, "Created project") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "single-file") != null);
    try std.testing.expect(std.mem.indexOf(u8, build_zig, "zypher-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, main_zig, "@import(\"zypher\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, main_zig, project_name) != null);
}

test "cli: new creates selected clean architecture template" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const project_name = try std.fmt.allocPrintSentinel(std.testing.allocator, "zypher_cli_clean_{s}", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(project_name);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, project_name) catch {};

    const args = [_][:0]const u8{ "zypher", "new", project_name, "--template", "clean-arch" };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    const cwd = std.Io.Dir.cwd();
    var root = try cwd.openDir(std.testing.io, project_name, .{});
    defer root.close(std.testing.io);
    var src = try root.openDir(std.testing.io, "src", .{});
    defer src.close(std.testing.io);
    var domain = try src.openDir(std.testing.io, "domain", .{});
    defer domain.close(std.testing.io);
    var application = try src.openDir(std.testing.io, "application", .{});
    defer application.close(std.testing.io);
    var infrastructure = try src.openDir(std.testing.io, "infrastructure", .{});
    defer infrastructure.close(std.testing.io);
    var presentation = try src.openDir(std.testing.io, "presentation", .{});
    defer presentation.close(std.testing.io);

    const service_zig = try application.readFileAlloc(std.testing.io, "home_service.zig", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(service_zig);

    try std.testing.expect(std.mem.indexOf(u8, output, "clean-arch") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_zig, project_name) != null);
}

test "cli: new accepts nested project paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const project_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/apps/nested_app", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(project_path);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, project_path) catch {};

    const args = [_][:0]const u8{ "zypher", "new", project_path, "--template", "single-file" };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    var root = try std.Io.Dir.cwd().openDir(std.testing.io, project_path, .{});
    defer root.close(std.testing.io);
    const main_zig = try root.readFileAlloc(std.testing.io, "src/main.zig", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(main_zig);

    try std.testing.expect(std.mem.indexOf(u8, output, project_path) != null);
    try std.testing.expect(std.mem.indexOf(u8, main_zig, "nested_app.db") != null);
}

test "cli: templates lists built-in scaffold templates" {
    const args = [_][:0]const u8{ "zypher", "templates" };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "single-file") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "clean-arch") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "mvc") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "mvp") != null);
}

test "cli: run builds zig build run argv with zypher root and passthrough args" {
    const app_args = [_][:0]const u8{ "--port", "9090" };
    const argv = try cli.buildRunArgv(std.testing.allocator, "/tmp/zypher", &app_args);
    defer {
        for (argv) |arg| std.testing.allocator.free(arg);
        std.testing.allocator.free(argv);
    }

    try std.testing.expectEqual(@as(usize, 7), argv.len);
    try std.testing.expectEqualStrings("zig", argv[0]);
    try std.testing.expectEqualStrings("build", argv[1]);
    try std.testing.expectEqualStrings("-Dzypher-root=/tmp/zypher", argv[2]);
    try std.testing.expectEqualStrings("run", argv[3]);
    try std.testing.expectEqualStrings("--", argv[4]);
    try std.testing.expectEqualStrings("--port", argv[5]);
    try std.testing.expectEqualStrings("9090", argv[6]);
}

test "cli: migrate applies SQL files in order and skips applied migrations" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = std.Io.Dir.cwd();
    const db_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/migrate.sqlite", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(db_path);
    const migrations_dir = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/migrations", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(migrations_dir);
    try cwd.createDirPath(std.testing.io, migrations_dir);

    const first_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/0001_create_users.sql", .{migrations_dir});
    defer std.testing.allocator.free(first_path);
    const second_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/0002_add_email.sql", .{migrations_dir});
    defer std.testing.allocator.free(second_path);
    try cwd.writeFile(std.testing.io, .{ .sub_path = first_path, .data = "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL);" });
    try cwd.writeFile(std.testing.io, .{ .sub_path = second_path, .data = "ALTER TABLE users ADD COLUMN email TEXT;" });

    const args = [_][:0]const u8{ "zypher", "migrate", "--db", db_path, "--dir", migrations_dir };
    const first_output = try runCli(&args);
    defer std.testing.allocator.free(first_output);
    const second_output = try runCli(&args);
    defer std.testing.allocator.free(second_output);

    try std.testing.expect(std.mem.indexOf(u8, first_output, "applied 2 migration(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, second_output, "applied 0 migration(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, second_output, "skipped 2") != null);

    var db = try sqlite.Db.open(std.testing.allocator, db_path);
    defer db.close();
    try db.exec("INSERT INTO users (name, email) VALUES ('alice', 'alice@example.com')");
    var stmt = try db.prepare("SELECT COUNT(*) FROM zypher_migrations");
    defer stmt.finalize();
    try std.testing.expect(try stmt.step());
    const count = try stmt.column(.integer, 0);
    try std.testing.expectEqual(@as(i64, 2), count.int);
}

test "cli: createsuperuser prompt creates active admin with hashed password" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/superuser.sqlite", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(db_path);

    var input = std.Io.Reader.fixed("admin@example.com\nStr0ngPass\n");
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var err = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer err.deinit();

    try cli.runCreatesuperuserPrompt(std.testing.allocator, db_path, &input, &out.writer, &err.writer);

    try std.testing.expectEqual(@as(usize, 0), err.written().len);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Email:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Password:") != null);

    var db = try sqlite.Db.open(std.testing.allocator, db_path);
    defer db.close();
    var stmt = try db.prepare("SELECT username, password_hash, role, is_active FROM users WHERE username = ?");
    defer stmt.finalize();
    try stmt.bind(.{ .text = "admin@example.com" }, 1);
    try std.testing.expect(try stmt.step());
    const username = try stmt.column(.text, 0);
    const password_hash = try stmt.column(.text, 1);
    const role = try stmt.column(.text, 2);
    const active = try stmt.column(.integer, 3);

    try std.testing.expectEqualStrings("admin@example.com", username.text);
    try std.testing.expect(!std.mem.eql(u8, password_hash.text, "Str0ngPass"));
    try std.testing.expect(try password.verify(password_hash.text, "Str0ngPass"));
    try std.testing.expectEqualStrings("admin", role.text);
    try std.testing.expectEqual(@as(i64, 1), active.int);
}

test "cli: createsuperuser validates email and password strength" {
    try std.testing.expectError(error.InvalidEmail, cli.validateSuperuserCredentials("not-email", "Str0ngPass"));
    try std.testing.expectError(error.WeakPassword, cli.validateSuperuserCredentials("admin@example.com", "weakpass"));
}

test "cli: runserver parses host and port options" {
    const args = [_][:0]const u8{ "zypher", "runserver", "--host", "0.0.0.0", "--port", "9001", "--max-requests", "1" };
    const config = try cli.parseRunserverConfig(&args);

    try std.testing.expectEqualStrings("0.0.0.0", config.host);
    try std.testing.expectEqual(@as(u16, 9001), config.port);
    try std.testing.expectEqual(@as(?usize, 1), config.max_requests);
}

test "cli: runserver default handler responds to health check" {
    var req = Request{
        .method = .get,
        .path = "/health",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    cli.runserverDefaultHandler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expectEqualStrings("OK", res.body.?);
}

test "cli: runserver SIGINT handler requests app shutdown" {
    var app = App.init(std.testing.allocator, .{ .host = "127.0.0.1", .port = 19088 });
    defer app.deinit();

    cli.bindRunserverSignalTarget(&app, std.testing.io);
    defer cli.clearRunserverSignalTarget();

    try std.testing.expect(!app.server.shutdown_requested.load(.acquire));
    var info: std.posix.siginfo_t = undefined;
    cli.runserverSigintHandler(.INT, &info, null);
    try std.testing.expect(app.server.shutdown_requested.load(.acquire));
}

test "cli: runserver serves health check and returns after max requests" {
    const port: u16 = 19089;
    const args = [_][:0]const u8{
        "zypher",
        "runserver",
        "--host",
        "127.0.0.1",
        "--port",
        "19089",
        "--max-requests",
        "1",
    };

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var err = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer err.deinit();

    const run_ctx = struct {
        fn run(
            out_writer: *std.Io.Writer,
            err_writer: *std.Io.Writer,
            argv: []const [:0]const u8,
        ) !void {
            try cli.dispatchInner(out_writer, err_writer, testInit(), "runserver", argv);
        }
    };

    var thread = try std.Thread.spawn(.{}, run_ctx.run, .{ &out.writer, &err.writer, &args });

    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", port);
    var stream = try connectWithRetry(&addr);

    var read_buf: [1024]u8 = undefined;
    var write_buf: [1024]u8 = undefined;
    var reader = stream.reader(std.testing.io, &read_buf);
    var writer = stream.writer(std.testing.io, &write_buf);

    try writer.interface.writeAll("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    try writer.interface.flush();

    const response = try reader.interface.takeDelimiterExclusive('\n');
    try std.testing.expect(std.mem.indexOf(u8, response, "200") != null);

    stream.close(std.testing.io);
    thread.join();

    try std.testing.expectEqual(@as(usize, 0), err.written().len);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Starting zypher server") != null);
}

test "cli: runserver responds to health check and stops on SIGINT" {
    const port: u16 = 19090;
    const args = [_][:0]const u8{
        "zypher",
        "runserver",
        "--host",
        "127.0.0.1",
        "--port",
        "19090",
    };

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var err = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer err.deinit();

    const run_ctx = struct {
        fn run(
            out_writer: *std.Io.Writer,
            err_writer: *std.Io.Writer,
            argv: []const [:0]const u8,
        ) !void {
            try cli.dispatchInner(out_writer, err_writer, testInit(), "runserver", argv);
        }
    };

    var thread = try std.Thread.spawn(.{}, run_ctx.run, .{ &out.writer, &err.writer, &args });

    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", port);
    var stream = try connectWithRetry(&addr);

    var read_buf: [1024]u8 = undefined;
    var write_buf: [1024]u8 = undefined;
    var reader = stream.reader(std.testing.io, &read_buf);
    var writer = stream.writer(std.testing.io, &write_buf);

    try writer.interface.writeAll("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    try writer.interface.flush();

    const response = try reader.interface.takeDelimiterExclusive('\n');
    try std.testing.expect(std.mem.indexOf(u8, response, "200") != null);

    try std.posix.raise(.INT);
    stream.close(std.testing.io);
    thread.join();

    try std.testing.expectEqual(@as(usize, 0), err.written().len);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Starting zypher server") != null);
}

fn connectWithRetry(addr: *const std.Io.net.IpAddress) !std.Io.net.Stream {
    var attempts: usize = 0;
    while (attempts < 50) : (attempts += 1) {
        return std.Io.net.IpAddress.connect(addr, std.testing.io, .{ .mode = .stream }) catch |err| switch (err) {
            error.ConnectionRefused => {
                try std.Thread.yield();
                continue;
            },
            else => return err,
        };
    }
    return error.ConnectionRefused;
}

test "cli: logs command invocation with redacted args and outcome" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/logged_superuser.sqlite", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(db_path);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    log.startCapture(std.testing.allocator, &buf);
    defer log.stopCapture();

    const args = [_][:0]const u8{ "zypher", "createsuperuser", "--db", db_path, "--email", "logged@example.com", "--password", "Secr3tPass" };
    const output = try runCli(&args);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, buf.items, "command invoked: createsuperuser") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "command completed: createsuperuser") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--email logged@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--password <redacted>") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Secr3tPass") == null);
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

test "cli: shell exposes context and explicit line-oriented contract" {
    var input = std.Io.Reader.fixed(":context\n:contract\n:quit\n");
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var err = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer err.deinit();

    try cli.runShellSession(&input, &out.writer, &err.writer);

    try std.testing.expectEqual(@as(usize, 0), err.written().len);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Context bindings") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "std") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "zypher") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "line-oriented expression shell") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "not a compiler-backed Zig REPL") != null);
}
