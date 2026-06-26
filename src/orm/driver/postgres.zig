const std = @import("std");
const build_config = @import("build_config");
const iface = @import("interface.zig");

pub const enabled = build_config.has_postgres;

pub const ColumnType = iface.ColumnType;
pub const Value = iface.Value;
pub const DbError = iface.DbError;

const log = std.log.scoped(.pg);

pub const PostgresDb = if (build_config.has_postgres) struct {
    const c = @import("postgres.zig").c_types;
    const Self = @This();

    handle: ?*c.PGconn,
    gpa: std.mem.Allocator,
    stmt_counter: u32,

    pub fn open(gpa: std.mem.Allocator, connstr: [:0]const u8) DbError!Self {
        const raw = c.PQconnectdb(connstr.ptr);
        if (raw == null or c.PQstatus(raw) != c.CONNECTION_OK) {
            const msg = if (raw) |r| std.mem.sliceTo(c.PQerrorMessage(r), 0) else "PQconnectdb returned null";
            log.err("PQconnectdb failed: {s}", .{msg});
            if (raw) |r| c.PQfinish(r);
            return error.OpenFailed;
        }
        log.debug("connected to PostgreSQL", .{});
        return .{ .handle = raw, .gpa = gpa, .stmt_counter = 0 };
    }

    pub fn close(self: *Self) void {
        if (self.handle) |h| {
            c.PQfinish(h);
            self.handle = null;
            log.debug("disconnected from PostgreSQL", .{});
        }
    }

    pub fn exec(self: *Self, sql: [:0]const u8) DbError!void {
        const h = self.handle orelse return error.ExecFailed;
        const res = c.PQexec(h, sql.ptr) orelse return error.ExecFailed;
        defer c.PQclear(res);
        const status = c.PQresultStatus(res);
        if (status == c.PGRES_FATAL_ERROR) {
            const msg = std.mem.sliceTo(c.PQresultErrorMessage(res), 0);
            log.err("exec failed: {s}", .{msg});
            return error.ExecFailed;
        }
        log.debug("exec: {s}", .{sql});
    }

    pub fn prepare(self: *Self, sql: [:0]const u8) DbError!PostgresStmt {
        const h = self.handle orelse return error.PrepareFailed;

        const translated = translatePlaceholders(std.mem.sliceTo(sql, 0), self.gpa) catch return error.PrepareFailed;
        defer self.gpa.free(translated);

        const name = allocStmtName(self.gpa, &self.stmt_counter) catch return error.PrepareFailed;
        defer self.gpa.free(name);

        const res = c.PQprepare(h, name.ptr, translated.ptr, 0, null) orelse {
            log.err("PQprepare returned null", .{});
            return error.PrepareFailed;
        };
        defer c.PQclear(res);
        if (c.PQresultStatus(res) == c.PGRES_FATAL_ERROR) {
            const msg = std.mem.sliceTo(c.PQresultErrorMessage(res), 0);
            log.err("prepare failed: {s}", .{msg});
            return error.PrepareFailed;
        }

        const param_count = countParams(sql);
        const held_name = self.gpa.dupe(u8, name) catch return error.PrepareFailed;
        const bind_values = self.gpa.alloc(iface.Value, @max(@as(usize, @intCast(param_count)), 1)) catch return error.PrepareFailed;
        for (bind_values) |*v| v.* = .null;

        log.debug("prepared: {s} as {s}", .{ std.mem.sliceTo(sql, 0), held_name });
        return .{
            .conn = h,
            .gpa = self.gpa,
            .stmt_name = held_name,
            .param_count = param_count,
            .bind_values = bind_values,
            .result = null,
            .current_row = 0,
            .executed = false,
            .allocated = false,
        };
    }

    pub fn lastInsertRowId(self: *Self) i64 {
        const h = self.handle orelse return 0;
        const res = c.PQexec(h, "SELECT lastval()") orelse return 0;
        defer c.PQclear(res);
        if (c.PQresultStatus(res) != c.PGRES_TUPLES_OK) return 0;
        if (c.PQntuples(res) < 1) return 0;
        const val = c.PQgetvalue(res, 0, 0);
        return std.fmt.parseInt(i64, std.mem.sliceTo(val, 0), 10) catch 0;
    }

    pub fn changes(self: *Self) i64 {
        _ = self;
        return 0;
    }

    pub const dialect: iface.Dialect = iface.PostgresDialect;

    pub fn asRelationalDb(self: *Self) iface.RelationalDb {
        return .{ .ptr = @ptrCast(self), .vtable = &DB_VTABLE };
    }

    const DB_VTABLE = iface.RelationalDb.VTable{
        .exec = dbExec,
        .prepare = dbPrepare,
        .lastInsertId = dbLastInsertId,
        .changes = dbChanges,
        .close = dbClose,
        .dialect = dbDialect,
    };

    fn dbExec(ptr: *anyopaque, sql: [:0]const u8) iface.DbError!void {
        const db: *Self = @ptrCast(@alignCast(ptr));
        try db.exec(sql);
    }

    fn dbPrepare(ptr: *anyopaque, sql: [:0]const u8) iface.DbError!iface.AnyStmt {
        const db: *Self = @ptrCast(@alignCast(ptr));
        var raw = try db.prepare(sql);
        const stmt = db.gpa.create(PostgresStmt) catch return error.AllocatorFailed;
        raw.allocated = true;
        stmt.* = raw;
        return stmt.asAnyStmt();
    }

    fn dbLastInsertId(ptr: *anyopaque) i64 {
        const db: *Self = @ptrCast(@alignCast(ptr));
        return db.lastInsertRowId();
    }

    fn dbChanges(ptr: *anyopaque) i64 {
        const db: *Self = @ptrCast(@alignCast(ptr));
        return db.changes();
    }

    fn dbClose(ptr: *anyopaque) void {
        const db: *Self = @ptrCast(@alignCast(ptr));
        db.close();
    }

    fn dbDialect(_: *anyopaque) iface.Dialect {
        return iface.PostgresDialect;
    }
} else void;

pub const PostgresStmt = if (build_config.has_postgres) struct {
    const c = @import("postgres.zig").c_types;
    const Self = @This();

    conn: *c.PGconn,
    gpa: std.mem.Allocator,
    stmt_name: []u8,
    param_count: c_int,
    bind_values: []iface.Value,
    result: ?*c.PGresult,
    current_row: c_int,
    executed: bool,
    allocated: bool = false,

    pub fn bind(self: *Self, value: iface.Value, idx: c_int) DbError!void {
        const slot: usize = @intCast(idx);
        if (slot < 1 or slot > self.bind_values.len) return error.BindFailed;
        self.bind_values[slot - 1] = value;
    }

    pub fn step(self: *Self) DbError!bool {
        if (!self.executed) {
            self.executed = true;
            self.current_row = 0;

            const n = @as(usize, @intCast(self.param_count));
            const values_buf = self.gpa.alloc(?[*:0]const u8, n) catch return error.AllocatorFailed;
            defer self.gpa.free(values_buf);
            const lengths_buf = self.gpa.alloc(c_int, n) catch return error.AllocatorFailed;
            defer self.gpa.free(lengths_buf);
            const formats_buf = self.gpa.alloc(c_int, n) catch return error.AllocatorFailed;
            defer self.gpa.free(formats_buf);

            var fmt_buf: [64]u8 = undefined;
            for (self.bind_values[0..n], 0..) |v, i| {
                formats_buf[i] = 0;
                switch (v) {
                    .null => {
                        values_buf[i] = null;
                        lengths_buf[i] = 0;
                    },
                    .text => |s| {
                        values_buf[i] = s.ptr;
                        lengths_buf[i] = @intCast(s.len);
                    },
                    .int => |n_val| {
                        const formatted = std.fmt.bufPrint(&fmt_buf, "{d}", .{n_val}) catch return error.BindFailed;
                        values_buf[i] = formatted.ptr;
                        lengths_buf[i] = @intCast(formatted.len);
                    },
                    .float => |f| {
                        const formatted = std.fmt.bufPrint(&fmt_buf, "{d}", .{f}) catch return error.BindFailed;
                        values_buf[i] = formatted.ptr;
                        lengths_buf[i] = @intCast(formatted.len);
                    },
                }
            }

            const res = c.PQexecPrepared(
                self.conn,
                self.stmt_name.ptr,
                self.param_count,
                if (n > 0) values_buf.ptr else null,
                if (n > 0) lengths_buf.ptr else null,
                if (n > 0) formats_buf.ptr else null,
                0,
            ) orelse return error.StepFailed;
            self.result = res;

            const status = c.PQresultStatus(res);
            if (status == c.PGRES_FATAL_ERROR) {
                const msg = std.mem.sliceTo(c.PQresultErrorMessage(res), 0);
                log.err("step failed: {s}", .{msg});
                return error.StepFailed;
            }
        }

        if (self.result) |res| {
            if (self.current_row < c.PQntuples(res)) {
                self.current_row += 1;
                return true;
            }
        }
        return false;
    }

    pub fn column(self: *Self, kind: iface.ColumnType, idx: c_int) DbError!iface.Value {
        const res = self.result orelse return error.ColumnFailed;
        const row = self.current_row - 1;
        if (row < 0 or row >= c.PQntuples(res)) return error.ColumnFailed;

        if (c.PQgetisnull(res, row, idx) != 0) return .null;

        const raw = c.PQgetvalue(res, row, idx);
        const slice = std.mem.sliceTo(raw, 0);

        return switch (kind) {
            .integer => .{
                .int = std.fmt.parseInt(i64, slice, 10) catch return error.ColumnFailed,
            },
            .float => .{
                .float = std.fmt.parseFloat(f64, slice) catch return error.ColumnFailed,
            },
            .text => .{
                .text = try self.gpa.dupe(u8, slice),
            },
            else => return error.ColumnFailed,
        };
    }

    pub fn columnType(self: *Self, idx: c_int) DbError!iface.ColumnType {
        const res = self.result orelse return error.ColumnFailed;
        const oid = c.PQftype(res, idx);
        return switch (oid) {
            c.INT8_OID, c.INT4_OID => .integer,
            c.FLOAT8_OID, c.FLOAT4_OID => .float,
            c.TEXT_OID, c.VARCHAR_OID, c.BPCHAR_OID => .text,
            else => .null,
        };
    }

    pub fn reset(self: *Self) DbError!void {
        if (self.result) |res| {
            c.PQclear(res);
            self.result = null;
        }
        self.executed = false;
        self.current_row = 0;
        for (self.bind_values) |*v| v.* = .null;
    }

    pub fn finalize(self: *Self) void {
        if (self.result) |res| {
            c.PQclear(res);
            self.result = null;
        }
        const h = self.conn;
        const dealloc_sql = std.fmt.allocPrint(self.gpa, "DEALLOCATE \"{s}\"", .{self.stmt_name}) catch null;
        if (dealloc_sql) |sql| {
            const dealloc_res = c.PQexec(h, sql.ptr);
            if (dealloc_res) |dr| c.PQclear(dr);
            self.gpa.free(sql);
        }
        self.gpa.free(self.stmt_name);
        self.gpa.free(self.bind_values);
        log.debug("finalized statement", .{});
    }

    pub fn asAnyStmt(self: *Self) iface.AnyStmt {
        return .{ .ptr = @ptrCast(self), .vtable = &STMT_VTABLE };
    }

    const STMT_VTABLE = iface.AnyStmt.VTable{
        .bind = stmtBind,
        .step = stmtStep,
        .column = stmtColumn,
        .columnType = stmtColumnType,
        .reset = stmtReset,
        .finalize = stmtFinalize,
    };

    fn stmtBind(ptr: *anyopaque, value: iface.Value, idx: c_int) iface.DbError!void {
        const stmt: *Self = @ptrCast(@alignCast(ptr));
        try stmt.bind(value, idx);
    }

    fn stmtStep(ptr: *anyopaque) iface.DbError!bool {
        const stmt: *Self = @ptrCast(@alignCast(ptr));
        return try stmt.step();
    }

    fn stmtColumn(ptr: *anyopaque, kind: iface.ColumnType, idx: c_int) iface.DbError!iface.Value {
        const stmt: *Self = @ptrCast(@alignCast(ptr));
        return try stmt.column(kind, idx);
    }

    fn stmtColumnType(ptr: *anyopaque, idx: c_int) iface.DbError!iface.ColumnType {
        const stmt: *Self = @ptrCast(@alignCast(ptr));
        return try stmt.columnType(idx);
    }

    fn stmtReset(ptr: *anyopaque) iface.DbError!void {
        const stmt: *Self = @ptrCast(@alignCast(ptr));
        try stmt.reset();
    }

    fn stmtFinalize(ptr: *anyopaque) void {
        const stmt: *Self = @ptrCast(@alignCast(ptr));
        stmt.finalize();
        if (stmt.allocated) stmt.gpa.destroy(stmt);
    }
} else void;

pub const c_types = if (build_config.has_postgres) struct {
    pub const PGconn = opaque {};
    pub const PGresult = opaque {};

    pub const CONNECTION_OK = 0;
    pub const PGRES_COMMAND_OK = 1;
    pub const PGRES_TUPLES_OK = 2;
    pub const PGRES_EMPTY_QUERY = 3;
    pub const PGRES_FATAL_ERROR = 7;

    pub extern fn PQconnectdb(conninfo: [*:0]const u8) ?*PGconn;
    pub extern fn PQfinish(conn: ?*PGconn) void;
    pub extern fn PQstatus(conn: *const PGconn) c_int;
    pub extern fn PQerrorMessage(conn: *const PGconn) [*:0]const u8;
    pub extern fn PQexec(conn: *PGconn, command: [*:0]const u8) ?*PGresult;
    pub extern fn PQprepare(
        conn: *PGconn,
        stmtName: [*:0]const u8,
        query: [*:0]const u8,
        nParams: c_int,
        paramTypes: ?*const u32,
    ) ?*PGresult;
    pub extern fn PQexecPrepared(
        conn: *PGconn,
        stmtName: [*:0]const u8,
        nParams: c_int,
        paramValues: ?*const ?[*:0]const u8,
        paramLengths: ?*const c_int,
        paramFormats: ?*const c_int,
        resultFormat: c_int,
    ) ?*PGresult;
    pub extern fn PQresultStatus(res: *const PGresult) c_int;
    pub extern fn PQresultErrorMessage(res: *const PGresult) [*:0]const u8;
    pub extern fn PQntuples(res: *const PGresult) c_int;
    pub extern fn PQnfields(res: *const PGresult) c_int;
    pub extern fn PQgetvalue(res: *const PGresult, row_number: c_int, column_number: c_int) [*:0]const u8;
    pub extern fn PQgetisnull(res: *const PGresult, row_number: c_int, column_number: c_int) c_int;
    pub extern fn PQgetlength(res: *const PGresult, row_number: c_int, column_number: c_int) c_int;
    pub extern fn PQclear(res: ?*PGresult) void;
    pub extern fn PQcmdTuples(res: *const PGresult) [*:0]const u8;
    pub extern fn PQoidValue(res: *const PGresult) u32;
    pub extern fn PQftype(res: *const PGresult, column_number: c_int) u32;

    pub const INT8_OID = 20;
    pub const INT4_OID = 23;
    pub const FLOAT8_OID = 701;
    pub const FLOAT4_OID = 700;
    pub const TEXT_OID = 25;
    pub const VARCHAR_OID = 1043;
    pub const BOOL_OID = 16;
    pub const BPCHAR_OID = 1042;
} else struct {};

fn countParams(sql: [:0]const u8) c_int {
    var count: c_int = 0;
    for (std.mem.sliceTo(sql, 0)) |ch| {
        if (ch == '?') count += 1;
    }
    return count;
}

fn allocStmtName(gpa: std.mem.Allocator, counter: *u32) ![]u8 {
    counter.* += 1;
    return std.fmt.allocPrint(gpa, "zypher_stmt_{d}", .{counter.*});
}

pub fn translatePlaceholders(input: []const u8, gpa: std.mem.Allocator) (error{AllocatorFailed}![]u8) {
    const count = countParams(input);
    if (count == 0) return gpa.dupe(u8, input);

    var result = std.ArrayList(u8).init(gpa);
    errdefer result.deinit();

    var param_idx: usize = 1;
    for (input) |ch| {
        if (ch == '?') {
            var ph_buf: [16]u8 = undefined;
            const placeholder = std.fmt.bufPrint(&ph_buf, "${d}", .{param_idx}) catch unreachable;
            try result.appendSlice(placeholder);
            param_idx += 1;
        } else {
            try result.append(ch);
        }
    }
    return result.toOwnedSlice();
}

test {
    std.testing.refAllDecls(@This());
}
