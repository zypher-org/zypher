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
        try cmdMakemigrations(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "shell")) {
        try cmdShell(out_writer, err_writer, init, args);
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

fn parseDbPath(args: []const [:0]const u8) ?[:0]const u8 {
    var i: usize = 2;
    while (i + 1 < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--db")) {
            return args[i + 1];
        }
    }
    return null;
}

// ── makemigrations ───────────────────────────────────────────────────────

const SchemaField = struct {
    table: []const u8,
    name: []const u8,
    kind: []const u8,
    primary: bool = false,
    required: bool = false,
    unique: bool = false,
    foreign: ?[]const u8 = null,
};

fn cmdMakemigrations(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const gpa = init.gpa;
    const io = init.io;

    var schema_path: []const u8 = "schema.zypher";
    var state_path: []const u8 = ".zypher_schema";
    var migrations_dir: []const u8 = "migrations";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--schema")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --schema requires a value\n", .{});
                std.process.exit(1);
            }
            schema_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--state")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --state requires a value\n", .{});
                std.process.exit(1);
            }
            state_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--dir")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --dir requires a value\n", .{});
                std.process.exit(1);
            }
            migrations_dir = args[i];
        } else {
            try err_writer.print("zypher: unknown option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }

    const cwd = std.Io.Dir.cwd();
    const schema_text = cwd.readFileAlloc(io, schema_path, gpa, .limited(1024 * 1024)) catch {
        try err_writer.print("zypher: failed to read schema manifest '{s}'\n", .{schema_path});
        std.process.exit(1);
    };
    defer gpa.free(schema_text);

    const state_text = cwd.readFileAlloc(io, state_path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => {
            try err_writer.print("zypher: failed to read schema snapshot '{s}'\n", .{state_path});
            std.process.exit(1);
        },
    };
    defer if (state_text) |text| gpa.free(text);

    var current = try parseSchemaManifest(gpa, schema_text);
    defer current.deinit(gpa);
    var previous = try parseSchemaManifest(gpa, state_text orelse "");
    defer previous.deinit(gpa);

    cwd.createDirPath(io, migrations_dir) catch {
        try err_writer.print("zypher: failed to create migrations directory '{s}'\n", .{migrations_dir});
        std.process.exit(1);
    };

    var created: usize = 0;
    if (previous.items.len == 0) {
        created = try writeInitialMigrations(gpa, io, migrations_dir, current.items, out_writer);
    } else {
        created = try writeAddedFieldMigrations(gpa, io, migrations_dir, previous.items, current.items, out_writer);
    }

    cwd.writeFile(io, .{ .sub_path = state_path, .data = schema_text }) catch {
        try err_writer.print("zypher: failed to write schema snapshot '{s}'\n", .{state_path});
        std.process.exit(1);
    };

    if (created == 0) {
        log.info("makemigrations found no schema changes", .{});
        try out_writer.print("No schema changes detected\n", .{});
    } else {
        log.info("makemigrations created {d} migration(s)", .{created});
    }
}

fn parseSchemaManifest(gpa: std.mem.Allocator, text: []const u8) !std.ArrayList(SchemaField) {
    var fields: std.ArrayList(SchemaField) = .empty;
    var current_table: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const head = parts.next() orelse continue;
        if (std.mem.eql(u8, head, "table")) {
            current_table = parts.next() orelse return error.InvalidMigrationManifest;
        } else if (std.mem.eql(u8, head, "field")) {
            const table = current_table orelse return error.InvalidMigrationManifest;
            var field = SchemaField{
                .table = table,
                .name = parts.next() orelse return error.InvalidMigrationManifest,
                .kind = parts.next() orelse return error.InvalidMigrationManifest,
            };
            while (parts.next()) |flag| {
                if (std.mem.eql(u8, flag, "primary")) {
                    field.primary = true;
                } else if (std.mem.eql(u8, flag, "required")) {
                    field.required = true;
                } else if (std.mem.eql(u8, flag, "unique")) {
                    field.unique = true;
                } else if (std.mem.startsWith(u8, flag, "foreign=")) {
                    field.foreign = flag["foreign=".len..];
                } else {
                    return error.InvalidMigrationManifest;
                }
            }
            try fields.append(gpa, field);
        } else {
            return error.InvalidMigrationManifest;
        }
    }

    return fields;
}

fn findField(fields: []const SchemaField, table: []const u8, name: []const u8) ?SchemaField {
    for (fields) |field| {
        if (std.mem.eql(u8, field.table, table) and std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}

fn writeAddedFieldMigrations(
    gpa: std.mem.Allocator,
    io: std.Io,
    migrations_dir: []const u8,
    previous: []const SchemaField,
    current: []const SchemaField,
    out_writer: *std.Io.Writer,
) !usize {
    var created: usize = 0;
    const cwd = std.Io.Dir.cwd();
    for (current) |field| {
        if (findField(previous, field.table, field.name) != null) continue;
        created += 1;
        const filename = try migrationFilename(gpa, migrations_dir, created, "add", field.name, "to", field.table);
        defer gpa.free(filename);
        const column = try columnSql(gpa, field, false);
        defer gpa.free(column);
        const sql = try std.fmt.allocPrint(gpa, "ALTER TABLE {s} ADD COLUMN {s} {s};\n", .{
            field.table,
            field.name,
            column,
        });
        defer gpa.free(sql);
        try cwd.writeFile(io, .{ .sub_path = filename, .data = sql });
        try out_writer.print("Created migration {s}: add_{s}_to_{s}\n", .{ filename, field.name, field.table });
    }
    return created;
}

fn writeInitialMigrations(
    gpa: std.mem.Allocator,
    io: std.Io,
    migrations_dir: []const u8,
    fields: []const SchemaField,
    out_writer: *std.Io.Writer,
) !usize {
    var created: usize = 0;
    const cwd = std.Io.Dir.cwd();
    for (fields, 0..) |field, field_idx| {
        if (tableAppearedBefore(fields[0..field_idx], field.table)) continue;
        var table_fields: std.ArrayList(SchemaField) = .empty;
        defer table_fields.deinit(gpa);
        for (fields) |candidate| {
            if (std.mem.eql(u8, candidate.table, field.table)) try table_fields.append(gpa, candidate);
        }
        created += 1;
        const filename = try migrationFilename(gpa, migrations_dir, created, "create", field.table, "", "");
        defer gpa.free(filename);
        var sql = std.Io.Writer.Allocating.init(gpa);
        defer sql.deinit();
        try sql.writer.print("CREATE TABLE IF NOT EXISTS {s} (", .{field.table});
        for (table_fields.items, 0..) |table_field, idx| {
            if (idx > 0) try sql.writer.writeAll(", ");
            const column = try columnSql(gpa, table_field, true);
            defer gpa.free(column);
            try sql.writer.print("{s} {s}", .{ table_field.name, column });
        }
        try sql.writer.writeAll(");\n");
        try cwd.writeFile(io, .{ .sub_path = filename, .data = sql.written() });
        try out_writer.print("Created migration {s}: create_{s}\n", .{ filename, field.table });
    }
    return created;
}

fn tableAppearedBefore(fields: []const SchemaField, table: []const u8) bool {
    for (fields) |field| {
        if (std.mem.eql(u8, field.table, table)) return true;
    }
    return false;
}

fn migrationFilename(
    gpa: std.mem.Allocator,
    migrations_dir: []const u8,
    index: usize,
    action: []const u8,
    subject: []const u8,
    middle: []const u8,
    object: []const u8,
) ![]u8 {
    if (middle.len == 0) {
        return std.fmt.allocPrint(gpa, "{s}/{d:0>4}_{s}_{s}.sql", .{ migrations_dir, index, action, subject });
    }
    return std.fmt.allocPrint(gpa, "{s}/{d:0>4}_{s}_{s}_{s}_{s}.sql", .{ migrations_dir, index, action, subject, middle, object });
}

fn columnSql(gpa: std.mem.Allocator, field: SchemaField, include_primary: bool) ![]u8 {
    const sql_type = if (std.mem.eql(u8, field.kind, "integer"))
        "INTEGER"
    else if (std.mem.eql(u8, field.kind, "float"))
        "REAL"
    else if (std.mem.eql(u8, field.kind, "text"))
        "TEXT"
    else if (std.mem.eql(u8, field.kind, "boolean"))
        "BOOLEAN"
    else
        return error.InvalidMigrationManifest;

    var sql = std.Io.Writer.Allocating.init(gpa);
    errdefer sql.deinit();
    try sql.writer.writeAll(sql_type);
    if (include_primary and field.primary) try sql.writer.writeAll(" PRIMARY KEY");
    if (field.required and !field.primary) try sql.writer.writeAll(" NOT NULL");
    if (field.unique and !field.primary) try sql.writer.writeAll(" UNIQUE");
    if (field.foreign) |target| try sql.writer.print(" REFERENCES {s}", .{target});
    return try sql.toOwnedSlice();
}

// ── shell ────────────────────────────────────────────────────────────────

fn cmdShell(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    var eval_expr: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--eval")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --eval requires an expression\n", .{});
                std.process.exit(1);
            }
            eval_expr = args[i];
        } else {
            try err_writer.print("zypher: unknown option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }

    const expr = eval_expr orelse {
        var stdin_buffer: [4096]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().reader(init.io, &stdin_buffer);
        try runShellSession(&stdin_reader.interface, out_writer, err_writer);
        return;
    };
    const value = evalIntegerExpression(expr) catch {
        try err_writer.print("zypher: invalid shell expression\n", .{});
        std.process.exit(1);
    };
    log.info("shell evaluated expression", .{});
    try out_writer.print("{d}\n", .{value});
}

/// Run an interactive zypher shell session from a line-oriented reader.
pub fn runShellSession(reader: *std.Io.Reader, out_writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    log.info("shell session started", .{});
    try out_writer.writeAll("zypher shell\n");
    try out_writer.writeAll("Context: std, zypher\n");
    try out_writer.writeAll("Commands: :help, :quit\n");

    while (true) {
        try out_writer.writeAll("zypher> ");
        const maybe_line = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => {
                log.err("shell read failed", .{});
                return err;
            },
            error.StreamTooLong => {
                log.err("shell input line exceeded reader buffer", .{});
                try err_writer.writeAll("zypher: input line too long\n");
                continue;
            },
        };
        const raw_line = maybe_line orelse break;
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;

        if (std.mem.eql(u8, line, ":quit") or std.mem.eql(u8, line, ":q") or std.mem.eql(u8, line, "exit")) {
            try out_writer.writeAll("bye\n");
            log.info("shell session ended", .{});
            return;
        }
        if (std.mem.eql(u8, line, ":help") or std.mem.eql(u8, line, ":h")) {
            try out_writer.writeAll("Available commands: :help, :quit\n");
            try out_writer.writeAll("Expressions: integer arithmetic with +, -, *, /\n");
            continue;
        }

        const value = evalIntegerExpression(line) catch {
            log.warn("shell rejected invalid expression", .{});
            try err_writer.print("zypher: invalid expression: {s}\n", .{line});
            continue;
        };
        try out_writer.print("{d}\n", .{value});
    }

    try out_writer.writeAll("bye\n");
    log.info("shell session ended at EOF", .{});
}

const ExprParser = struct {
    input: []const u8,
    pos: usize = 0,

    fn skipSpace(self: *ExprParser) void {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) self.pos += 1;
    }

    fn parseExpr(self: *ExprParser) !i64 {
        var lhs = try self.parseTerm();
        while (true) {
            self.skipSpace();
            if (self.pos >= self.input.len) return lhs;
            const op = self.input[self.pos];
            if (op != '+' and op != '-') return lhs;
            self.pos += 1;
            const rhs = try self.parseTerm();
            lhs = if (op == '+') lhs + rhs else lhs - rhs;
        }
    }

    fn parseTerm(self: *ExprParser) !i64 {
        var lhs = try self.parseNumber();
        while (true) {
            self.skipSpace();
            if (self.pos >= self.input.len) return lhs;
            const op = self.input[self.pos];
            if (op != '*' and op != '/') return lhs;
            self.pos += 1;
            const rhs = try self.parseNumber();
            lhs = if (op == '*') lhs * rhs else @divTrunc(lhs, rhs);
        }
    }

    fn parseNumber(self: *ExprParser) !i64 {
        self.skipSpace();
        const start = self.pos;
        if (self.pos < self.input.len and (self.input[self.pos] == '-' or self.input[self.pos] == '+')) self.pos += 1;
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) self.pos += 1;
        if (self.pos == start) return error.InvalidShellExpression;
        return std.fmt.parseInt(i64, self.input[start..self.pos], 10);
    }
};

fn evalIntegerExpression(expr: []const u8) !i64 {
    var parser = ExprParser{ .input = expr };
    const value = try parser.parseExpr();
    parser.skipSpace();
    if (parser.pos != expr.len) return error.InvalidShellExpression;
    return value;
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
        const path = try std.fmt.allocPrint(init.gpa, "{s}/examples", .{project_name});
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
    try out_writer.print("  {s}/examples/\n", .{project_name});
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
