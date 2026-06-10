/// CLI dispatch logic — testable separately from the binary entry point.
const std = @import("std");
const builtin = @import("builtin");
const App = @import("../core/app.zig").App;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const sqlite = @import("../orm/sqlite.zig");
const migration = @import("../orm/migration.zig");
const password = @import("../auth/password.zig");
const validators = @import("../forms/validators.zig");
const static_files = @import("../middleware/static.zig");
const zypher_log = @import("../log.zig");
const log = std.log.scoped(.cli);

pub const RunserverConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    max_requests: ?usize = null,
};

var runserver_signal_app: ?*App = null;
var runserver_signal_io: ?std.Io = null;
const supports_posix_signals = builtin.os.tag != .windows and builtin.os.tag != .wasi;
const RunserverSigintState = if (supports_posix_signals) std.posix.Sigaction else void;
var docs_server_root: []const u8 = "zig-out/docs";
var docs_server_io: ?std.Io = null;

pub fn dispatchInner(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    cmd: []const u8,
    args: []const [:0]const u8,
) !void {
    logCliCommand("invoked", cmd, args);
    defer logCliCommand("completed", cmd, args);

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
    } else if (std.mem.eql(u8, cmd, "templates")) {
        try cmdTemplates(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try cmdRun(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "doc")) {
        try cmdDoc(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "doc-user")) {
        try cmdDocUser(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "demo")) {
        try cmdDemo(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "makemigrations")) {
        try cmdMakemigrations(out_writer, err_writer, init, args);
    } else if (std.mem.eql(u8, cmd, "shell")) {
        try cmdShell(out_writer, err_writer, init, args);
    } else {
        try err_writer.print("zypher: unknown command '{s}'\n", .{cmd});
        std.process.exit(1);
    }
}

fn logCliCommand(event: []const u8, cmd: []const u8, args: []const [:0]const u8) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;

    appendLog(&buf, &pos, "command {s}: {s}", .{ event, cmd });
    if (args.len > 2) {
        appendLog(&buf, &pos, " args=", .{});
        var redact_next = false;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (i > 2) appendLog(&buf, &pos, " ", .{});
            if (redact_next) {
                appendLog(&buf, &pos, "<redacted>", .{});
                redact_next = false;
                continue;
            }
            appendLog(&buf, &pos, "{s}", .{args[i]});
            if (isSensitiveCliArg(args[i])) redact_next = true;
        }
    }

    zypher_log.writeLog(.info, "cli", buf[0..pos]);
}

fn appendLog(buf: []u8, pos: *usize, comptime fmt: []const u8, args: anytype) void {
    if (pos.* >= buf.len) return;
    const written = std.fmt.bufPrint(buf[pos.*..], fmt, args) catch {
        const suffix = "...";
        const remaining = buf.len - pos.*;
        const n = @min(remaining, suffix.len);
        @memcpy(buf[pos.* .. pos.* + n], suffix[0..n]);
        pos.* += n;
        return;
    };
    pos.* += written.len;
}

fn isSensitiveCliArg(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--password") or
        std.mem.eql(u8, arg, "--db-password") or
        std.mem.eql(u8, arg, "--secret") or
        std.mem.eql(u8, arg, "--token");
}

fn printHelp(w: *std.Io.Writer) !void {
    try w.print("zypher — Django-inspired web framework for Zig\n", .{});
    try w.print("Usage: zypher <command> [options]\n\n", .{});
    try w.print("Commands:\n", .{});
    try w.print("  new <path>         Create a new project from a scaffold template\n", .{});
    try w.print("  templates          List scaffold templates\n", .{});
    try w.print("  run [path]         Run a scaffolded app via its build.zig (--port defaults to 8080)\n", .{});
    try w.print("  doc                Build and serve zypher library documentation\n", .{});
    try w.print("  doc-user [path]    Build and serve documentation for user code\n", .{});
    try w.print("  demo <name>        Create a demo project with template rendering\n", .{});
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
    try out_writer.writeAll("Commands: :help, :context, :contract, :quit\n");

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
            try out_writer.writeAll("Available commands: :help, :context, :contract, :quit\n");
            try out_writer.writeAll("Expressions: integer arithmetic with +, -, *, /\n");
            continue;
        }
        if (std.mem.eql(u8, line, ":context")) {
            try writeShellContext(out_writer);
            continue;
        }
        if (std.mem.eql(u8, line, ":contract")) {
            try writeShellContract(out_writer);
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

fn writeShellContext(out_writer: *std.Io.Writer) !void {
    try out_writer.writeAll("Context bindings:\n");
    try out_writer.writeAll("  std    Zig standard library namespace\n");
    try out_writer.writeAll("  zypher Framework public API namespace\n");
}

fn writeShellContract(out_writer: *std.Io.Writer) !void {
    try out_writer.writeAll("This is a line-oriented expression shell with zypher context metadata; it is not a compiler-backed Zig REPL.\n");
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
    var email: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, args[i], "--email")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --email requires a value\n", .{});
                std.process.exit(1);
            }
            email = args[i];
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

    if (username == null or email == null or plain_password == null) {
        var stdin_buffer: [4096]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().reader(init.io, &stdin_buffer);
        runCreatesuperuserInteractive(gpa, db_path, &stdin_reader.interface, out_writer, err_writer) catch |err| {
            try printSuperuserError(err_writer, err);
            std.process.exit(1);
        };
        return;
    }

    const row_id = createSuperuser(gpa, db_path, .{
        .username = username.?,
        .email = email.?,
        .password = plain_password.?,
    }) catch |err| {
        try printSuperuserError(err_writer, err);
        std.process.exit(1);
    };
    try out_writer.print("Superuser '{s}' created (id={d})\n", .{ username.?, row_id });
}

pub const SuperuserInput = struct {
    username: []const u8,
    email: []const u8,
    password: []const u8,
};

/// Validate createsuperuser credentials before writing to the database.
pub fn validateSuperuserCredentials(input: SuperuserInput) !void {
    if (std.mem.trim(u8, input.username, " \t\r\n").len == 0) return error.InvalidUsername;
    if (validators.email(input.email) != null) return error.InvalidEmail;
    if (input.password.len < 8) return error.WeakPassword;

    var has_letter = false;
    var has_digit = false;
    for (input.password) |ch| {
        if (std.ascii.isAlphabetic(ch)) has_letter = true;
        if (std.ascii.isDigit(ch)) has_digit = true;
    }
    if (!has_letter or !has_digit) return error.WeakPassword;
}

/// Prompt for superuser credentials and create the admin account.
pub fn runCreatesuperuserPrompt(
    gpa: std.mem.Allocator,
    db_path: [:0]const u8,
    reader: *std.Io.Reader,
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
) !void {
    _ = err_writer;
    try out_writer.writeAll("Username: ");
    try out_writer.flush();
    const username = try readPromptLine(gpa, reader);
    defer gpa.free(username);
    try out_writer.writeAll("Email: ");
    try out_writer.flush();
    const email = try readPromptLine(gpa, reader);
    defer gpa.free(email);
    try out_writer.writeAll("Password: ");
    try out_writer.flush();
    const plain_password = try readPromptLine(gpa, reader);
    defer gpa.free(plain_password);
    try out_writer.writeAll("Confirm password: ");
    try out_writer.flush();
    const confirm_password = try readPromptLine(gpa, reader);
    defer gpa.free(confirm_password);
    if (!std.mem.eql(u8, plain_password, confirm_password)) return error.PasswordMismatch;

    const row_id = try createSuperuser(gpa, db_path, .{
        .username = username,
        .email = email,
        .password = plain_password,
    });
    try out_writer.print("Superuser '{s}' created (id={d})\n", .{ username, row_id });
}

fn runCreatesuperuserInteractive(
    gpa: std.mem.Allocator,
    db_path: [:0]const u8,
    reader: *std.Io.Reader,
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
) !void {
    _ = err_writer;
    try out_writer.writeAll("Username: ");
    try out_writer.flush();
    const username = try readPromptLine(gpa, reader);
    defer gpa.free(username);
    try out_writer.writeAll("Email: ");
    try out_writer.flush();
    const email = try readPromptLine(gpa, reader);
    defer gpa.free(email);
    try out_writer.writeAll("Password: ");
    try out_writer.flush();
    const plain_password = try readHiddenPromptLine(gpa, reader, out_writer);
    defer gpa.free(plain_password);
    try out_writer.writeAll("Confirm password: ");
    try out_writer.flush();
    const confirm_password = try readHiddenPromptLine(gpa, reader, out_writer);
    defer gpa.free(confirm_password);
    if (!std.mem.eql(u8, plain_password, confirm_password)) return error.PasswordMismatch;

    const row_id = try createSuperuser(gpa, db_path, .{
        .username = username,
        .email = email,
        .password = plain_password,
    });
    try out_writer.print("Superuser '{s}' created (id={d})\n", .{ username, row_id });
}

fn readPromptLine(gpa: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    const raw = (try reader.takeDelimiter('\n')) orelse return error.MissingPromptValue;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return error.MissingPromptValue;
    return gpa.dupe(u8, trimmed);
}

fn readHiddenPromptLine(gpa: std.mem.Allocator, reader: *std.Io.Reader, out_writer: *std.Io.Writer) ![]u8 {
    if (supports_posix_terminal) {
        const stdin_fd = std.Io.File.stdin().handle;
        var term = std.posix.tcgetattr(stdin_fd) catch return readPromptLine(gpa, reader);
        const old = term;
        term.lflag.ECHO = false;
        std.posix.tcsetattr(stdin_fd, .NOW, term) catch return readPromptLine(gpa, reader);
        defer std.posix.tcsetattr(stdin_fd, .NOW, old) catch {};
        const line = try readPromptLine(gpa, reader);
        try out_writer.writeAll("\n");
        return line;
    }
    return readPromptLine(gpa, reader);
}

const supports_posix_terminal = builtin.os.tag != .windows and builtin.os.tag != .wasi;

fn ensureUserSchema(db: *sqlite.Db) !void {
    db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  username TEXT NOT NULL UNIQUE,
        \\  email TEXT UNIQUE,
        \\  password_hash TEXT NOT NULL,
        \\  role TEXT NOT NULL DEFAULT 'user',
        \\  is_active INTEGER NOT NULL DEFAULT 1,
        \\  reset_code TEXT,
        \\  reset_code_expires_at INTEGER
        \\)
    ) catch {
        return error.CreateUserTableFailed;
    };
    if (!userColumnExists(db, "email")) db.exec("ALTER TABLE users ADD COLUMN email TEXT") catch {};
    if (!userColumnExists(db, "reset_code")) db.exec("ALTER TABLE users ADD COLUMN reset_code TEXT") catch {};
    if (!userColumnExists(db, "reset_code_expires_at")) db.exec("ALTER TABLE users ADD COLUMN reset_code_expires_at INTEGER") catch {};
    db.exec("CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique ON users(email)") catch {};
}

fn userColumnExists(db: *sqlite.Db, name: []const u8) bool {
    var stmt = db.prepare("PRAGMA table_info(users)") catch return false;
    defer stmt.finalize();
    while (stmt.step() catch false) {
        const column_name = stmt.column(.text, 1) catch continue;
        if (std.mem.eql(u8, column_name.text, name)) return true;
    }
    return false;
}

fn createSuperuser(gpa: std.mem.Allocator, db_path: [:0]const u8, input: SuperuserInput) !i64 {
    try validateSuperuserCredentials(input);

    var db = sqlite.Db.open(gpa, db_path) catch {
        return error.OpenDatabaseFailed;
    };
    defer db.close();

    try ensureUserSchema(&db);

    const hash_str = password.hash(gpa, input.password) catch return error.HashPasswordFailed;
    defer gpa.free(hash_str);

    var stmt = db.prepare("INSERT INTO users (username, email, password_hash, role, is_active) VALUES (?, ?, ?, 'admin', 1)") catch {
        return error.PrepareUserInsertFailed;
    };
    defer stmt.finalize();

    stmt.bind(.{ .text = input.username }, 1) catch {
        return error.BindUserInsertFailed;
    };
    stmt.bind(.{ .text = input.email }, 2) catch {
        return error.BindUserInsertFailed;
    };
    stmt.bind(.{ .text = hash_str }, 3) catch {
        return error.BindUserInsertFailed;
    };

    _ = stmt.step() catch {
        return error.CreateUserFailed;
    };

    const row_id = db.lastInsertRowId();
    log.info("created superuser '{s}' (id={d}, role=admin)", .{ input.username, row_id });
    return row_id;
}

fn printSuperuserError(err_writer: *std.Io.Writer, err: anyerror) !void {
    switch (err) {
        error.InvalidUsername => try err_writer.writeAll("zypher: username is required\n"),
        error.InvalidEmail => try err_writer.writeAll("zypher: invalid email address\n"),
        error.WeakPassword => try err_writer.writeAll("zypher: password must be at least 8 characters and include a letter and a digit\n"),
        error.PasswordMismatch => try err_writer.writeAll("zypher: passwords do not match\n"),
        error.MissingPromptValue => try err_writer.writeAll("zypher: username, email, and password are required\n"),
        error.OpenDatabaseFailed => try err_writer.writeAll("zypher: failed to open database\n"),
        error.CreateUserTableFailed => try err_writer.writeAll("zypher: failed to create users table\n"),
        error.HashPasswordFailed => try err_writer.writeAll("zypher: failed to hash password\n"),
        error.PrepareUserInsertFailed => try err_writer.writeAll("zypher: failed to prepare insert\n"),
        error.BindUserInsertFailed => try err_writer.writeAll("zypher: failed to bind user data\n"),
        error.CreateUserFailed => try err_writer.writeAll("zypher: failed to create user (username or email may already exist)\n"),
        else => try err_writer.writeAll("zypher: failed to create superuser\n"),
    }
}

// ── migrate ───────────────────────────────────────────────────────────────

fn cmdMigrate(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const gpa = init.gpa;
    const io = init.io;
    var db_path: [:0]const u8 = "db.sqlite";
    var migrations_dir: []const u8 = "migrations";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--db")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --db requires a value\n", .{});
                std.process.exit(1);
            }
            db_path = args[i];
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

    const result = applyMigrationDirectory(gpa, io, &db, migrations_dir) catch {
        try err_writer.print("zypher: failed to apply migrations from '{s}'\n", .{migrations_dir});
        std.process.exit(1);
    };
    try out_writer.print("zypher: database '{s}' — applied {d} migration(s), skipped {d}\n", .{ db_path, result.applied, result.skipped });
    if (result.total == 0) {
        try out_writer.print("zypher: no migrations found in '{s}'. Use zypher makemigrations first.\n", .{migrations_dir});
    }
}

const MigrateResult = struct {
    total: usize = 0,
    applied: usize = 0,
    skipped: usize = 0,
};

fn applyMigrationDirectory(gpa: std.mem.Allocator, io: std.Io, db: *sqlite.Db, migrations_dir: []const u8) !MigrateResult {
    var files = try collectMigrationFiles(gpa, io, migrations_dir);
    defer {
        for (files.items) |name| gpa.free(name);
        files.deinit(gpa);
    }

    std.mem.sort([]u8, files.items, {}, migrationNameLessThan);

    var result = MigrateResult{ .total = files.items.len };
    for (files.items) |name| {
        const id = try migrationIdFromFilename(name);
        if (try cliMigrationApplied(db, id)) {
            result.skipped += 1;
            log.info("skipping already-applied migration {d}: {s}", .{ id, name });
            continue;
        }

        const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ migrations_dir, name });
        defer gpa.free(path);
        const sql = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
        defer gpa.free(sql);
        const sql_z = try gpa.dupeSentinel(u8, sql, 0);
        defer gpa.free(sql_z);

        db.exec(sql_z) catch {
            log.err("migration {d} ({s}) failed", .{ id, name });
            return error.MigrationApplyFailed;
        };
        try recordCliMigration(db, id, name);
        result.applied += 1;
        log.info("applied migration {d}: {s}", .{ id, name });
    }
    return result;
}

fn collectMigrationFiles(gpa: std.mem.Allocator, io: std.Io, migrations_dir: []const u8) !std.ArrayList([]u8) {
    var files: std.ArrayList([]u8) = .empty;
    errdefer {
        for (files.items) |name| gpa.free(name);
        files.deinit(gpa);
    }

    var dir = std.Io.Dir.cwd().openDir(io, migrations_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return files,
        else => return err,
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".sql")) continue;
        try files.append(gpa, try gpa.dupe(u8, entry.name));
    }
    return files;
}

fn migrationNameLessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn migrationIdFromFilename(name: []const u8) !i64 {
    var end: usize = 0;
    while (end < name.len and std.ascii.isDigit(name[end])) end += 1;
    if (end == 0) return error.InvalidMigrationFilename;
    return std.fmt.parseInt(i64, name[0..end], 10);
}

fn cliMigrationApplied(db: *sqlite.Db, id: i64) !bool {
    var stmt = try db.prepare("SELECT id FROM zypher_migrations WHERE id = ?");
    defer stmt.finalize();
    try stmt.bind(.{ .int = id }, 1);
    return try stmt.step();
}

fn recordCliMigration(db: *sqlite.Db, id: i64, name: []const u8) !void {
    var stmt = try db.prepare("INSERT INTO zypher_migrations (id, name) VALUES (?, ?)");
    defer stmt.finalize();
    try stmt.bind(.{ .int = id }, 1);
    try stmt.bind(.{ .text = name }, 2);
    _ = try stmt.step();
}

// ── project scaffolding ───────────────────────────────────────────────────

const default_template_name = "single-file";
const default_template_dir = "templates";
const default_zypher_root = "../..";

const NewOptions = struct {
    project_path: []const u8,
    project_name: []const u8,
    template_name: []const u8 = default_template_name,
    template_dir: []const u8 = default_template_dir,
    api: bool = false,
};

const RunOptions = struct {
    project_path: []const u8 = ".",
    zypher_root: ?[]const u8 = null,
    port: u16 = 8080,
    app_args_start: usize,
};

const DocOptions = struct {
    project_path: []const u8 = ".",
    zypher_root: []const u8 = ".",
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    max_requests: ?usize = null,
};

fn cmdNew(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const opts = parseNewOptions(err_writer, args) catch return;
    try validateProjectName(err_writer, opts.project_name);
    try scaffoldProject(out_writer, err_writer, init, opts);
}

fn parseNewOptions(err_writer: *std.Io.Writer, args: []const [:0]const u8) !NewOptions {
    if (args.len < 3) {
        try err_writer.print("zypher: new requires a project name\n", .{});
        std.process.exit(1);
    }
    const project_path = std.mem.trim(u8, args[2], std.fs.path.sep_str);
    if (project_path.len == 0) {
        try err_writer.print("zypher: project path cannot be empty\n", .{});
        std.process.exit(1);
    }
    var opts = NewOptions{
        .project_path = project_path,
        .project_name = projectBaseName(project_path),
    };
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--template") or std.mem.eql(u8, args[i], "--style")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: {s} requires a value\n", .{args[i - 1]});
                std.process.exit(1);
            }
            opts.template_name = args[i];
        } else if (std.mem.eql(u8, args[i], "--template-dir")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --template-dir requires a value\n", .{});
                std.process.exit(1);
            }
            opts.template_dir = args[i];
        } else if (std.mem.eql(u8, args[i], "--api")) {
            opts.api = true;
        } else {
            try err_writer.print("zypher: unknown new option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }
    return opts;
}

fn projectBaseName(project_path: []const u8) []const u8 {
    return std.fs.path.basename(project_path);
}

fn projectDirName(project_path: []const u8) ?[]const u8 {
    const dirname = std.fs.path.dirname(project_path) orelse return null;
    if (dirname.len == 0 or std.mem.eql(u8, dirname, ".")) return null;
    return dirname;
}

fn validateProjectName(err_writer: *std.Io.Writer, project_name: []const u8) !void {
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
}

fn scaffoldProject(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    opts: NewOptions,
) !void {
    const io = init.io;
    const gpa = init.gpa;

    const cwd = std.Io.Dir.cwd();
    if (projectDirName(opts.project_path)) |parent| cwd.createDirPath(io, parent) catch {
        try err_writer.print("zypher: failed to create parent directory '{s}'\n", .{parent});
        std.process.exit(1);
    };
    cwd.createDir(io, opts.project_path, .default_dir) catch {
        try err_writer.print("zypher: failed to create directory '{s}'\n", .{opts.project_path});
        std.process.exit(1);
    };

    const source_template = if (opts.api)
        try std.fmt.allocPrint(gpa, "{s}-api", .{opts.template_name})
    else
        try gpa.dupe(u8, opts.template_name);
    defer gpa.free(source_template);

    const source_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ opts.template_dir, source_template });
    defer gpa.free(source_path);

    var source_dir = cwd.openDir(io, source_path, .{ .iterate = true }) catch {
        try err_writer.print("zypher: template '{s}' not found in {s}\n", .{ source_template, opts.template_dir });
        cwd.deleteTree(io, opts.project_path) catch {};
        std.process.exit(1);
    };
    defer source_dir.close(io);

    copyTemplateDir(gpa, io, source_dir, cwd, opts.project_path, opts.project_name) catch {
        try err_writer.print("zypher: failed to copy template '{s}'\n", .{source_template});
        cwd.deleteTree(io, opts.project_path) catch {};
        std.process.exit(1);
    };

    log.info("scaffolded project '{s}' from template '{s}'", .{ opts.project_path, source_template });
    try out_writer.print("Created project '{s}' from template '{s}'\n", .{ opts.project_path, source_template });
    try out_writer.print("  cd {s}\n", .{opts.project_path});
    try out_writer.print("  zypher run\n", .{});
}

fn copyTemplateDir(
    gpa: std.mem.Allocator,
    io: std.Io,
    source_dir: std.Io.Dir,
    dest_root: std.Io.Dir,
    project_root: []const u8,
    project_name: []const u8,
) !void {
    var walker = try source_dir.walk(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (isGeneratedTemplatePath(entry.path)) continue;

        const replaced_rel = try replaceProjectName(gpa, entry.path, project_name);
        defer gpa.free(replaced_rel);
        const dest_path = try std.fs.path.join(gpa, &.{ project_root, replaced_rel });
        defer gpa.free(dest_path);

        switch (entry.kind) {
            .directory => try dest_root.createDirPath(io, dest_path),
            .file => {
                if (std.fs.path.dirname(dest_path)) |parent| {
                    try dest_root.createDirPath(io, parent);
                }
                const data = try source_dir.readFileAlloc(io, entry.path, gpa, .limited(1024 * 1024));
                defer gpa.free(data);
                const rendered = try replaceProjectName(gpa, data, project_name);
                defer gpa.free(rendered);
                try dest_root.writeFile(io, .{ .sub_path = dest_path, .data = rendered });
            },
            else => {},
        }
    }
}

fn isGeneratedTemplatePath(path: []const u8) bool {
    var parts = std.mem.splitScalar(u8, path, std.fs.path.sep);
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".zig-cache")) return true;
        if (std.mem.eql(u8, part, "zig-out")) return true;
    }
    return false;
}

fn replaceProjectName(gpa: std.mem.Allocator, input: []const u8, project_name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var rest = input;
    while (std.mem.indexOf(u8, rest, "{{project_name}}")) |idx| {
        try out.appendSlice(gpa, rest[0..idx]);
        try out.appendSlice(gpa, project_name);
        rest = rest[idx + "{{project_name}}".len ..];
    }
    try out.appendSlice(gpa, rest);
    return out.toOwnedSlice(gpa);
}

fn cmdTemplates(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const io = init.io;
    var template_dir: []const u8 = default_template_dir;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--template-dir")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --template-dir requires a value\n", .{});
                std.process.exit(1);
            }
            template_dir = args[i];
        } else {
            try err_writer.print("zypher: unknown templates option '{s}'\n", .{args[i]});
            std.process.exit(1);
        }
    }

    var dir = std.Io.Dir.cwd().openDir(io, template_dir, .{ .iterate = true }) catch {
        try err_writer.print("zypher: template directory '{s}' not found\n", .{template_dir});
        std.process.exit(1);
    };
    defer dir.close(io);

    try out_writer.print("Available templates in {s}:\n", .{template_dir});
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .directory) try out_writer.print("  {s}\n", .{entry.name});
    }
}

fn cmdRun(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const opts = parseRunOptions(err_writer, args) catch return;
    const zypher_root = if (opts.zypher_root) |root|
        try init.gpa.dupe(u8, root)
    else
        inferZypherRoot(init.gpa, init.io) catch {
            try err_writer.print("zypher: failed to locate Zypher source tree; pass --zypher-root <path>\n", .{});
            std.process.exit(1);
        };
    defer init.gpa.free(zypher_root);

    const argv = try buildRunArgv(init.gpa, zypher_root, opts.port, args[opts.app_args_start..]);
    defer freeArgv(init.gpa, argv);

    try out_writer.print("Running app in {s}\n", .{opts.project_path});
    var child = std.process.spawn(init.io, .{
        .argv = argv,
        .cwd = .{ .path = opts.project_path },
    }) catch {
        try err_writer.print("zypher: failed to spawn zig build run\n", .{});
        std.process.exit(1);
    };
    const term = child.wait(init.io) catch {
        try err_writer.print("zypher: failed while waiting for app process\n", .{});
        std.process.exit(1);
    };
    if (!term.success()) {
        try err_writer.print("zypher: app process {t}\n", .{term});
        std.process.exit(1);
    }
}

fn parseRunOptions(err_writer: *std.Io.Writer, args: []const [:0]const u8) !RunOptions {
    var opts = RunOptions{ .app_args_start = args.len };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--")) {
            opts.app_args_start = i + 1;
            break;
        } else if (std.mem.eql(u8, args[i], "--zypher-root")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --zypher-root requires a value\n", .{});
                std.process.exit(1);
            }
            opts.zypher_root = args[i];
        } else if (std.mem.eql(u8, args[i], "--port")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --port requires a value\n", .{});
                std.process.exit(1);
            }
            opts.port = std.fmt.parseInt(u16, args[i], 10) catch {
                try err_writer.print("zypher: invalid --port value '{s}'\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, args[i], "--")) {
            try err_writer.print("zypher: unknown run option '{s}'\n", .{args[i]});
            std.process.exit(1);
        } else {
            opts.project_path = args[i];
        }
    }
    return opts;
}

pub fn inferZypherRoot(gpa: std.mem.Allocator, io: std.Io) ![]const u8 {
    const exe_dir = std.process.executableDirPathAlloc(io, gpa) catch {
        return gpa.dupe(u8, default_zypher_root);
    };
    defer gpa.free(exe_dir);

    if (try candidateZypherRootFromExeDir(gpa, io, exe_dir)) |root| return root;
    if (try candidateZypherRootFromPath(gpa, io, ".")) |root| return root;
    return gpa.dupe(u8, default_zypher_root);
}

fn candidateZypherRootFromExeDir(gpa: std.mem.Allocator, io: std.Io, exe_dir: []const u8) !?[]const u8 {
    const bin_dir = std.fs.path.basename(exe_dir);
    if (!std.mem.eql(u8, bin_dir, "bin")) return null;

    const zig_out_dir = std.fs.path.dirname(exe_dir) orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(zig_out_dir), "zig-out")) return null;

    const root = std.fs.path.dirname(zig_out_dir) orelse return null;
    return candidateZypherRootFromPath(gpa, io, root);
}

fn candidateZypherRootFromPath(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, root, ".")) {
        std.Io.Dir.cwd().access(io, "src/zypher.zig", .{}) catch return null;
        return try gpa.dupe(u8, root);
    }

    const zypher_file = try std.fs.path.join(gpa, &.{ root, "src", "zypher.zig" });
    defer gpa.free(zypher_file);

    std.Io.Dir.accessAbsolute(io, zypher_file, .{}) catch return null;
    return try gpa.dupe(u8, root);
}

pub fn buildRunArgv(gpa: std.mem.Allocator, zypher_root: []const u8, port: u16, app_args: []const [:0]const u8) ![][]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (argv.items) |arg| gpa.free(arg);
        argv.deinit(gpa);
    }

    try argv.append(gpa, try gpa.dupe(u8, "zig"));
    try argv.append(gpa, try gpa.dupe(u8, "build"));
    try argv.append(gpa, try std.fmt.allocPrint(gpa, "-Dzypher-root={s}", .{zypher_root}));
    try argv.append(gpa, try gpa.dupe(u8, "run"));
    try argv.append(gpa, try gpa.dupe(u8, "--"));
    try argv.append(gpa, try gpa.dupe(u8, "--port"));
    try argv.append(gpa, try std.fmt.allocPrint(gpa, "{d}", .{port}));
    if (app_args.len > 0) {
        for (app_args) |arg| try argv.append(gpa, try gpa.dupe(u8, arg));
    }
    return argv.toOwnedSlice(gpa);
}

pub fn buildDocArgv(gpa: std.mem.Allocator) ![][]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (argv.items) |arg| gpa.free(arg);
        argv.deinit(gpa);
    }

    try argv.append(gpa, try gpa.dupe(u8, "zig"));
    try argv.append(gpa, try gpa.dupe(u8, "build"));
    try argv.append(gpa, try gpa.dupe(u8, "doc"));
    return argv.toOwnedSlice(gpa);
}

fn freeArgv(gpa: std.mem.Allocator, argv: [][]const u8) void {
    for (argv) |arg| gpa.free(arg);
    gpa.free(argv);
}

fn cmdDoc(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const opts = parseDocOptions(err_writer, args, .framework) catch return;
    try buildAndServeDocs(out_writer, err_writer, init, opts.zypher_root, opts);
}

fn cmdDocUser(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const opts = parseDocOptions(err_writer, args, .user) catch return;
    try buildAndServeDocs(out_writer, err_writer, init, opts.project_path, opts);
}

const DocMode = enum {
    framework,
    user,
};

fn parseDocOptions(err_writer: *std.Io.Writer, args: []const [:0]const u8, mode: DocMode) !DocOptions {
    var opts = DocOptions{};
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--zypher-root")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --zypher-root requires a value\n", .{});
                std.process.exit(1);
            }
            opts.zypher_root = args[i];
        } else if (std.mem.eql(u8, args[i], "--host")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --host requires a value\n", .{});
                std.process.exit(1);
            }
            opts.host = args[i];
        } else if (std.mem.eql(u8, args[i], "--port")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --port requires a value\n", .{});
                std.process.exit(1);
            }
            opts.port = std.fmt.parseInt(u16, args[i], 10) catch {
                try err_writer.print("zypher: invalid --port value '{s}'\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, args[i], "--max-requests")) {
            i += 1;
            if (i >= args.len) {
                try err_writer.print("zypher: --max-requests requires a value\n", .{});
                std.process.exit(1);
            }
            opts.max_requests = std.fmt.parseInt(usize, args[i], 10) catch {
                try err_writer.print("zypher: invalid --max-requests value '{s}'\n", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, args[i], "--")) {
            try err_writer.print("zypher: unknown documentation option '{s}'\n", .{args[i]});
            std.process.exit(1);
        } else if (mode == .user) {
            opts.project_path = args[i];
        } else {
            try err_writer.print("zypher: doc does not accept a project path; use --zypher-root\n", .{});
            std.process.exit(1);
        }
    }
    return opts;
}

fn buildAndServeDocs(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    build_cwd: []const u8,
    opts: DocOptions,
) !void {
    const argv = try buildDocArgv(init.gpa);
    defer freeArgv(init.gpa, argv);

    try out_writer.print("Building documentation in {s}\n", .{build_cwd});
    var child = std.process.spawn(init.io, .{
        .argv = argv,
        .cwd = .{ .path = build_cwd },
    }) catch {
        try err_writer.print("zypher: failed to spawn zig build doc\n", .{});
        std.process.exit(1);
    };
    const term = child.wait(init.io) catch {
        try err_writer.print("zypher: failed while waiting for documentation build\n", .{});
        std.process.exit(1);
    };
    if (!term.success()) {
        try err_writer.print("zypher: documentation build {t}\n", .{term});
        std.process.exit(1);
    }

    const docs_root = try std.fs.path.join(init.gpa, &.{ build_cwd, "zig-out", "docs" });
    defer init.gpa.free(docs_root);
    docs_server_root = docs_root;
    docs_server_io = init.io;
    defer docs_server_io = null;

    try out_writer.print("Serving documentation at http://{s}:{d}/\n", .{ opts.host, opts.port });
    var app = App.init(init.gpa, .{
        .host = opts.host,
        .port = opts.port,
        .max_requests = opts.max_requests,
    });
    defer app.deinit();
    app.handler_fn = docsHandler;

    bindRunserverSignalTarget(&app, init.io);
    defer clearRunserverSignalTarget();
    const old_sigint = installRunserverSigintHandler();
    defer restoreRunserverSigintHandler(old_sigint);

    try app.listenAndServe(init.io);
}

fn docsHandler(req: *Request, res: *Response) void {
    if (req.method != .get and req.method != .head) {
        _ = res.status(405);
        res.text("Method Not Allowed") catch {};
        return;
    }

    var rel = req.path;
    while (std.mem.startsWith(u8, rel, "/")) rel = rel[1..];
    if (rel.len == 0) rel = "index.html";
    if (hasPathTraversal(rel)) {
        _ = res.status(403);
        res.text("Forbidden") catch {};
        return;
    }

    const fs_path = std.fs.path.join(res.allocator, &.{ docs_server_root, rel }) catch {
        _ = res.status(500);
        res.text("Internal Server Error") catch {};
        return;
    };
    defer res.allocator.free(fs_path);

    const io = docs_server_io orelse {
        _ = res.status(500);
        res.text("Internal Server Error") catch {};
        return;
    };
    const body = std.Io.Dir.cwd().readFileAlloc(io, fs_path, res.allocator, .limited(32 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.NotDir, error.IsDir => {
            _ = res.status(404);
            res.text("Not Found") catch {};
            return;
        },
        else => {
            _ = res.status(500);
            res.text("Internal Server Error") catch {};
            return;
        },
    };

    if (res.body) |old| res.allocator.free(old);
    res.body = body;
    _ = res.header("Content-Type", static_files.detectMime(rel));
}

fn hasPathTraversal(path: []const u8) bool {
    var iter = std.mem.splitSequence(u8, path, "/");
    while (iter.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}

// ── demo (scaffold a small demo project) ──────────────────────────────────

fn cmdDemo(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    if (args.len < 3) {
        try err_writer.print("zypher: demo requires a project name\n", .{});
        std.process.exit(1);
    }
    const project_path = std.mem.trim(u8, args[2], std.fs.path.sep_str);
    const opts = NewOptions{ .project_path = project_path, .project_name = projectBaseName(project_path), .template_name = "mvc" };
    try validateProjectName(err_writer, opts.project_name);
    try scaffoldProject(out_writer, err_writer, init, opts);
}

// ── runserver ─────────────────────────────────────────────────────────────

pub fn parseRunserverConfig(args: []const [:0]const u8) !RunserverConfig {
    var config: RunserverConfig = .{};

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port")) {
            i += 1;
            if (i >= args.len) return error.MissingPort;
            config.port = std.fmt.parseInt(u16, args[i], 10) catch return error.InvalidPort;
        } else if (std.mem.eql(u8, args[i], "--host")) {
            i += 1;
            if (i >= args.len) return error.MissingHost;
            config.host = args[i];
        } else if (std.mem.eql(u8, args[i], "--max-requests")) {
            i += 1;
            if (i >= args.len) return error.MissingMaxRequests;
            config.max_requests = std.fmt.parseInt(usize, args[i], 10) catch return error.InvalidMaxRequests;
        } else {
            return error.UnknownOption;
        }
    }

    return config;
}

pub fn runserverDefaultHandler(req: *Request, res: *Response) void {
    if (std.mem.eql(u8, req.path, "/health")) {
        res.text("OK") catch {};
        return;
    }

    res.text("zypher server is running") catch {};
}

pub fn bindRunserverSignalTarget(app: *App, io: std.Io) void {
    runserver_signal_app = app;
    runserver_signal_io = io;
}

pub fn clearRunserverSignalTarget() void {
    runserver_signal_app = null;
    runserver_signal_io = null;
}

pub const runserverSigintHandler = if (supports_posix_signals)
    struct {
        fn handle(sig: std.posix.SIG, info: *const std.posix.siginfo_t, context: ?*anyopaque) callconv(.c) void {
            _ = sig;
            _ = info;
            _ = context;
            if (runserver_signal_app) |app| {
                if (runserver_signal_io) |io| {
                    app.shutdown(io);
                }
            }
        }
    }.handle
else
    struct {
        fn handle() void {}
    }.handle;

fn installRunserverSigintHandler() RunserverSigintState {
    if (!supports_posix_signals) return {};

    const act: std.posix.Sigaction = .{
        .handler = .{ .sigaction = runserverSigintHandler },
        .mask = std.posix.sigemptyset(),
        .flags = std.posix.SA.SIGINFO,
    };
    var old: std.posix.Sigaction = undefined;
    std.posix.sigaction(.INT, &act, &old);
    return old;
}

fn restoreRunserverSigintHandler(old: RunserverSigintState) void {
    if (!supports_posix_signals) return;

    var previous: std.posix.Sigaction = undefined;
    std.posix.sigaction(.INT, &old, &previous);
}

fn cmdRunserver(
    out_writer: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    init: std.process.Init,
    args: []const [:0]const u8,
) !void {
    const gpa = init.gpa;
    const config = parseRunserverConfig(args) catch |err| {
        switch (err) {
            error.MissingPort => try err_writer.print("zypher: --port requires a value\n", .{}),
            error.InvalidPort => try err_writer.print("zypher: invalid port\n", .{}),
            error.MissingHost => try err_writer.print("zypher: --host requires a value\n", .{}),
            error.MissingMaxRequests => try err_writer.print("zypher: --max-requests requires a value\n", .{}),
            error.InvalidMaxRequests => try err_writer.print("zypher: invalid max request count\n", .{}),
            error.UnknownOption => try err_writer.print("zypher: invalid runserver option\n", .{}),
        }
        std.process.exit(1);
    };

    log.info("runserver starting on {s}:{d}", .{ config.host, config.port });
    try out_writer.print("Starting zypher server at http://{s}:{d}/\n", .{ config.host, config.port });

    var app = App.init(gpa, .{ .host = config.host, .port = config.port, .max_requests = config.max_requests });
    defer app.deinit();

    app.handler_fn = runserverDefaultHandler;

    bindRunserverSignalTarget(&app, init.io);
    defer clearRunserverSignalTarget();
    const old_sigint = installRunserverSigintHandler();
    defer restoreRunserverSigintHandler(old_sigint);

    try app.listenAndServe(init.io);
}
