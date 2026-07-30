const std = @import("std");
const build_config = @import("build_config");
const iface = @import("interface.zig");

pub const enabled = build_config.has_mysql;

pub const ColumnType = iface.ColumnType;
pub const Value = iface.Value;
pub const DbError = iface.DbError;

const log = std.log.scoped(.mysql);

pub const c = if (build_config.has_mysql) struct {
    pub const MYSQL = opaque {};
    pub const MYSQL_STMT = opaque {};
    pub const MYSQL_RES = opaque {};
    pub const MYSQL_FIELD = extern struct {
        name: [*:0]const u8,
        org_name: [*:0]const u8,
        table: [*:0]const u8,
        org_table: [*:0]const u8,
        db: [*:0]const u8,
        catalog: [*:0]const u8,
        def: [*:0]const u8,
        length: c_ulong,
        max_length: c_ulong,
        name_length: c_uint,
        org_name_length: c_uint,
        table_length: c_uint,
        org_table_length: c_uint,
        db_length: c_uint,
        catalog_length: c_uint,
        def_length: c_uint,
        flags: c_uint,
        decimals: c_uint,
        charsetnr: c_uint,
        type: c_uint,
    };
    pub const MYSQL_BIND = extern struct {
        length: ?*c_ulong,
        is_null: ?*u8,
        buffer: ?*anyopaque,
        err_ptr: ?*u8,
        buffer_length: c_ulong,
        offset: c_ulong,
        internal_length: c_ulong,
        flags: c_ulong,
        buffer_type: c_uint,
    };

    pub const MYSQL_TYPE_DECIMAL = 0;
    pub const MYSQL_TYPE_TINY = 1;
    pub const MYSQL_TYPE_SHORT = 2;
    pub const MYSQL_TYPE_LONG = 3;
    pub const MYSQL_TYPE_FLOAT = 4;
    pub const MYSQL_TYPE_DOUBLE = 5;
    pub const MYSQL_TYPE_NULL = 6;
    pub const MYSQL_TYPE_LONGLONG = 8;
    pub const MYSQL_TYPE_VARCHAR = 15;
    pub const MYSQL_TYPE_STRING = 254;

    pub extern fn mysql_init(mysql: ?*MYSQL) ?*MYSQL;
    pub extern fn mysql_real_connect(
        mysql: ?*MYSQL,
        host: ?[*:0]const u8,
        user: ?[*:0]const u8,
        passwd: ?[*:0]const u8,
        db: ?[*:0]const u8,
        port: c_uint,
        unix_socket: ?[*:0]const u8,
        clientflag: c_ulong,
    ) ?*MYSQL;
    pub extern fn mysql_close(mysql: ?*MYSQL) void;
    pub extern fn mysql_error(mysql: *const MYSQL) [*:0]const u8;
    pub extern fn mysql_errno(mysql: *const MYSQL) c_uint;
    pub extern fn mysql_query(mysql: ?*MYSQL, query: [*:0]const u8) c_int;
    pub extern fn mysql_affected_rows(mysql: ?*MYSQL) u64;
    pub extern fn mysql_insert_id(mysql: ?*MYSQL) u64;
    pub extern fn mysql_stmt_init(mysql: ?*MYSQL) ?*MYSQL_STMT;
    pub extern fn mysql_stmt_prepare(stmt: ?*MYSQL_STMT, query: [*:0]const u8, length: c_ulong) c_int;
    pub extern fn mysql_stmt_execute(stmt: ?*MYSQL_STMT) c_int;
    pub extern fn mysql_stmt_bind_param(stmt: ?*MYSQL_STMT, bind: ?*MYSQL_BIND) c_int;
    pub extern fn mysql_stmt_bind_result(stmt: ?*MYSQL_STMT, bind: ?*MYSQL_BIND) c_int;
    pub extern fn mysql_stmt_fetch(stmt: ?*MYSQL_STMT) c_int;
    pub extern fn mysql_stmt_fetch_column(stmt: ?*MYSQL_STMT, bind: ?*MYSQL_BIND, column: c_uint, offset: c_ulong) c_int;
    pub extern fn mysql_stmt_store_result(stmt: ?*MYSQL_STMT) c_int;
    pub extern fn mysql_stmt_num_rows(stmt: ?*MYSQL_STMT) u64;
    pub extern fn mysql_stmt_close(stmt: ?*MYSQL_STMT) c_int;
    pub extern fn mysql_stmt_reset(stmt: ?*MYSQL_STMT) c_int;
    pub extern fn mysql_stmt_error(stmt: *const MYSQL_STMT) [*:0]const u8;
    pub extern fn mysql_stmt_result_metadata(stmt: ?*MYSQL_STMT) ?*MYSQL_RES;
    pub extern fn mysql_num_fields(res: *const MYSQL_RES) c_uint;
    pub extern fn mysql_fetch_fields(res: *const MYSQL_RES) [*]MYSQL_FIELD;
    pub extern fn mysql_free_result(res: ?*MYSQL_RES) void;

    pub const MYSQL_NO_DATA = 100;
    pub const MYSQL_DATA_TRUNCATED = 101;
} else struct {};

pub const MysqlConfig = if (build_config.has_mysql) struct {
    host: [:0]const u8 = "127.0.0.1",
    user: [:0]const u8 = "root",
    pass: [:0]const u8 = "",
    db: [:0]const u8,
    port: u16 = 3306,
} else void;

const ParamBuf = if (build_config.has_mysql) union(enum) {
    int: i64,
    float: f64,
    text: []u8,
    null: void,
} else void;

pub const MysqlDb = if (build_config.has_mysql) struct {
    const Self = @This();

    conn: ?*c.MYSQL,
    gpa: std.mem.Allocator,

    pub fn open(gpa: std.mem.Allocator, config: MysqlConfig) DbError!Self {
        const raw = c.mysql_init(null) orelse {
            log.err("mysql_init failed", .{});
            return error.OpenFailed;
        };
        const connected = c.mysql_real_connect(
            raw,
            config.host.ptr,
            config.user.ptr,
            config.pass.ptr,
            config.db.ptr,
            config.port,
            null,
            0,
        );
        if (connected == null) {
            const msg = std.mem.sliceTo(c.mysql_error(raw), 0);
            log.warn("mysql_real_connect failed: {s}", .{msg});
            c.mysql_close(raw);
            return error.OpenFailed;
        }
        log.debug("connected to MySQL at {s}:{d}", .{ config.host, config.port });
        return .{ .conn = connected, .gpa = gpa };
    }

    pub fn close(self: *Self) void {
        if (self.conn) |h| {
            c.mysql_close(h);
            self.conn = null;
            log.debug("disconnected from MySQL", .{});
        }
    }

    pub fn exec(self: *Self, sql: [:0]const u8) DbError!void {
        const h = self.conn orelse return error.ExecFailed;
        const rc = c.mysql_query(h, sql.ptr);
        if (rc != 0) {
            const msg = std.mem.sliceTo(c.mysql_error(h), 0);
            log.err("query failed: {s}", .{msg});
            return error.ExecFailed;
        }
        log.debug("exec: {s}", .{sql});
    }

    pub fn prepare(self: *Self, sql: [:0]const u8) DbError!MysqlStmt {
        const h = self.conn orelse return error.PrepareFailed;
        const raw = c.mysql_stmt_init(h) orelse {
            log.err("mysql_stmt_init failed", .{});
            return error.PrepareFailed;
        };
        const sql_len: c_ulong = @intCast(std.mem.sliceTo(sql.ptr, 0).len);
        const rc = c.mysql_stmt_prepare(raw, sql.ptr, sql_len);
        if (rc != 0) {
            const msg = std.mem.sliceTo(c.mysql_stmt_error(raw), 0);
            log.err("mysql_stmt_prepare failed: {s}", .{msg});
            _ = c.mysql_stmt_close(raw);
            return error.PrepareFailed;
        }
        const param_count = countPlaceholders(sql);
        const bind_values = self.gpa.alloc(iface.Value, @max(param_count, 1)) catch {
            _ = c.mysql_stmt_close(raw);
            return error.AllocatorFailed;
        };
        for (bind_values) |*v| v.* = .null;

        const param_bufs = self.gpa.alloc(ParamBuf, @max(param_count, 1)) catch {
            self.gpa.free(bind_values);
            _ = c.mysql_stmt_close(raw);
            return error.AllocatorFailed;
        };
        for (param_bufs) |*pb| pb.* = .null;

        log.debug("prepared: {s}", .{std.mem.sliceTo(sql, 0)});
        return .{
            .conn = h,
            .gpa = self.gpa,
            .stmt = raw,
            .param_count = @intCast(param_count),
            .bind_values = bind_values,
            .param_bufs = param_bufs,
            .result_meta = null,
            .current_row = 0,
            .executed = false,
            .allocated = false,
        };
    }

    pub fn lastInsertRowId(self: *Self) i64 {
        const h = self.conn orelse return 0;
        return @intCast(c.mysql_insert_id(h));
    }

    pub fn changes(self: *Self) i64 {
        const h = self.conn orelse return 0;
        return @intCast(c.mysql_affected_rows(h));
    }

    pub const dialect: iface.Dialect = iface.MysqlDialect;

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
        const stmt = db.gpa.create(MysqlStmt) catch return error.AllocatorFailed;
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
        return iface.MysqlDialect;
    }
} else void;

pub const MysqlStmt = if (build_config.has_mysql) struct {
    const Self = @This();

    conn: *c.MYSQL,
    gpa: std.mem.Allocator,
    stmt: *c.MYSQL_STMT,
    param_count: c_int,
    bind_values: []iface.Value,
    param_bufs: []ParamBuf,
    result_meta: ?*c.MYSQL_RES,
    current_row: c_int,
    executed: bool,
    allocated: bool = false,

    pub fn bind(self: *Self, value: iface.Value, idx: c_int) DbError!void {
        const slot: usize = @intCast(idx);
        if (slot < 1 or slot > self.bind_values.len) return error.BindFailed;
        self.bind_values[slot - 1] = value;

        if (value == .text) {
            const owned = self.gpa.dupe(u8, value.text) catch return error.AllocatorFailed;
            if (self.param_bufs[slot - 1] == .text) {
                self.gpa.free(self.param_bufs[slot - 1].text);
            }
            self.param_bufs[slot - 1] = .{ .text = owned };
        } else {
            switch (value) {
                .int => |iv| self.param_bufs[slot - 1] = .{ .int = iv },
                .float => |fv| self.param_bufs[slot - 1] = .{ .float = fv },
                .null => self.param_bufs[slot - 1] = .null,
                else => {},
            }
        }
    }

    pub fn step(self: *Self) DbError!bool {
        if (!self.executed) {
            self.executed = true;
            self.current_row = 0;

            const n = @as(usize, @intCast(self.param_count));
            const binds = self.gpa.alloc(c.MYSQL_BIND, @max(n, 1)) catch return error.AllocatorFailed;
            defer self.gpa.free(binds);

            for (binds, 0..) |*b, i| {
                b.* = std.mem.zeroes(c.MYSQL_BIND);
                if (i >= n) break;
                switch (self.param_bufs[i]) {
                    .null => {
                        b.buffer_type = c.MYSQL_TYPE_NULL;
                    },
                    .int => {
                        b.buffer_type = c.MYSQL_TYPE_LONGLONG;
                        b.buffer = @ptrCast(&self.param_bufs[i].int);
                        b.buffer_length = @sizeOf(i64);
                    },
                    .float => {
                        b.buffer_type = c.MYSQL_TYPE_DOUBLE;
                        b.buffer = @ptrCast(&self.param_bufs[i].float);
                        b.buffer_length = @sizeOf(f64);
                    },
                    .text => |s| {
                        b.buffer_type = c.MYSQL_TYPE_STRING;
                        b.buffer = s.ptr;
                        b.buffer_length = @intCast(s.len);
                    },
                }
            }

            if (c.mysql_stmt_bind_param(self.stmt, &binds[0]) != 0) {
                const msg = std.mem.sliceTo(c.mysql_stmt_error(self.stmt), 0);
                log.err("mysql_stmt_bind_param failed: {s}", .{msg});
                return error.BindFailed;
            }

            if (c.mysql_stmt_execute(self.stmt) != 0) {
                const msg = std.mem.sliceTo(c.mysql_stmt_error(self.stmt), 0);
                log.err("mysql_stmt_execute failed: {s}", .{msg});
                return error.StepFailed;
            }

            if (c.mysql_stmt_store_result(self.stmt) != 0) {
                const msg = std.mem.sliceTo(c.mysql_stmt_error(self.stmt), 0);
                log.err("mysql_stmt_store_result failed: {s}", .{msg});
                return error.StepFailed;
            }

            self.result_meta = c.mysql_stmt_result_metadata(self.stmt);
        }

        const fetch_rc = c.mysql_stmt_fetch(self.stmt);
        if (fetch_rc == c.MYSQL_NO_DATA) return false;
        if (fetch_rc != 0) return error.StepFailed;
        self.current_row += 1;
        return true;
    }

    pub fn column(self: *Self, kind: iface.ColumnType, idx: c_int) DbError!iface.Value {
        var col_bind = std.mem.zeroes(c.MYSQL_BIND);
        var buf: [4096]u8 = undefined;
        var is_null: u8 = 0;
        var length: c_ulong = 0;

        col_bind.buffer = &buf;
        col_bind.buffer_length = buf.len;
        col_bind.is_null = &is_null;
        col_bind.length = &length;

        switch (kind) {
            .integer => {
                col_bind.buffer_type = c.MYSQL_TYPE_LONGLONG;
                if (c.mysql_stmt_fetch_column(self.stmt, &col_bind, @intCast(idx), 0) != 0) {
                    return error.ColumnFailed;
                }
                if (is_null != 0) return .null;
                const ptr: *i64 = @ptrCast(@alignCast(&buf));
                return .{ .int = ptr.* };
            },
            .float => {
                col_bind.buffer_type = c.MYSQL_TYPE_DOUBLE;
                if (c.mysql_stmt_fetch_column(self.stmt, &col_bind, @intCast(idx), 0) != 0) {
                    return error.ColumnFailed;
                }
                if (is_null != 0) return .null;
                const ptr: *f64 = @ptrCast(@alignCast(&buf));
                return .{ .float = ptr.* };
            },
            .text => {
                col_bind.buffer_type = c.MYSQL_TYPE_STRING;
                if (c.mysql_stmt_fetch_column(self.stmt, &col_bind, @intCast(idx), 0) != 0) {
                    return error.ColumnFailed;
                }
                if (is_null != 0) return .null;
                return .{ .text = self.gpa.dupe(u8, buf[0..@as(usize, @intCast(length))]) catch return error.AllocatorFailed };
            },
            else => return error.ColumnFailed,
        }
    }

    pub fn columnType(self: *Self, idx: c_int) DbError!iface.ColumnType {
        const meta = self.result_meta orelse return error.ColumnFailed;
        const fields = c.mysql_fetch_fields(meta);
        const field_type = fields[@as(usize, @intCast(idx))].type;
        return switch (field_type) {
            c.MYSQL_TYPE_LONGLONG, c.MYSQL_TYPE_LONG, c.MYSQL_TYPE_SHORT, c.MYSQL_TYPE_TINY => .integer,
            c.MYSQL_TYPE_DOUBLE, c.MYSQL_TYPE_FLOAT => .float,
            c.MYSQL_TYPE_STRING, c.MYSQL_TYPE_VARCHAR => .text,
            else => .null,
        };
    }

    pub fn reset(self: *Self) DbError!void {
        if (self.result_meta) |rm| {
            c.mysql_free_result(rm);
            self.result_meta = null;
        }
        if (c.mysql_stmt_reset(self.stmt) != 0) {
            return error.BindFailed;
        }
        self.executed = false;
        self.current_row = 0;
        for (self.bind_values) |*v| v.* = .null;
        for (self.param_bufs) |*pb| {
            if (pb.* == .text) {
                self.gpa.free(pb.text);
            }
            pb.* = .null;
        }
    }

    pub fn finalize(self: *Self) void {
        if (self.result_meta) |rm| {
            c.mysql_free_result(rm);
            self.result_meta = null;
        }
        _ = c.mysql_stmt_close(self.stmt);
        for (self.param_bufs) |*pb| {
            if (pb.* == .text) {
                self.gpa.free(pb.text);
            }
        }
        self.gpa.free(self.param_bufs);
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

fn countPlaceholders(sql: [:0]const u8) usize {
    var count: usize = 0;
    for (std.mem.sliceTo(sql, 0)) |ch| {
        if (ch == '?') count += 1;
    }
    return count;
}

test {
    std.testing.refAllDecls(@This());
}
