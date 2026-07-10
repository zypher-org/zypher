/// zypher ORM — SQLite3 driver implementation.
/// Manual extern declarations (Zig 0.17 removed @cImport).
/// Conforms to the RelationalDb vtable interface.
const std = @import("std");
const iface = @import("interface.zig");

const log = std.log.scoped(.sqlite);

const c = struct {
    pub const sqlite3 = opaque {};
    pub const sqlite3_stmt = opaque {};

    pub const SQLITE_OK = 0;
    pub const SQLITE_ROW = 100;
    pub const SQLITE_DONE = 101;
    pub const SQLITE_INTEGER = 1;
    pub const SQLITE_FLOAT = 2;
    pub const SQLITE_TEXT = 3;
    pub const SQLITE_BLOB = 4;
    pub const SQLITE_NULL = 5;
    pub const SQLITE_CONSTRAINT = 19;

    const destructor_type = *align(1) const fn (?*anyopaque) callconv(.c) void;
    pub const SQLITE_TRANSIENT: destructor_type = @ptrFromInt(std.math.maxInt(usize));

    pub extern fn sqlite3_open(path: [*:0]const u8, handle: *?*sqlite3) c_int;
    pub extern fn sqlite3_close(handle: ?*sqlite3) c_int;
    pub extern fn sqlite3_exec(
        db: ?*sqlite3,
        sql: [*:0]const u8,
        callback: ?*const fn (?*anyopaque, c_int, ?*anyopaque, ?*anyopaque) callconv(.c) c_int,
        arg: ?*anyopaque,
        errmsg: ?*?*anyopaque,
    ) c_int;
    pub extern fn sqlite3_errmsg(db: ?*sqlite3) [*:0]const u8;
    pub extern fn sqlite3_prepare_v2(
        db: ?*sqlite3,
        sql: [*:0]const u8,
        nbytes: c_int,
        stmt: *?*sqlite3_stmt,
        tail: ?*?*const u8,
    ) c_int;
    pub extern fn sqlite3_last_insert_rowid(db: ?*sqlite3) i64;
    pub extern fn sqlite3_changes(db: ?*sqlite3) c_int;
    pub extern fn sqlite3_finalize(stmt: ?*sqlite3_stmt) c_int;
    pub extern fn sqlite3_reset(stmt: ?*sqlite3_stmt) c_int;
    pub extern fn sqlite3_bind_int64(stmt: ?*sqlite3_stmt, idx: c_int, value: i64) c_int;
    pub extern fn sqlite3_bind_double(stmt: ?*sqlite3_stmt, idx: c_int, value: f64) c_int;
    pub extern fn sqlite3_bind_text(stmt: ?*sqlite3_stmt, idx: c_int, text: [*]const u8, len: c_int, destructor: destructor_type) c_int;
    pub extern fn sqlite3_bind_null(stmt: ?*sqlite3_stmt, idx: c_int) c_int;
    pub extern fn sqlite3_step(stmt: ?*sqlite3_stmt) c_int;
    pub extern fn sqlite3_column_type(stmt: ?*sqlite3_stmt, idx: c_int) c_int;
    pub extern fn sqlite3_column_int64(stmt: ?*sqlite3_stmt, idx: c_int) i64;
    pub extern fn sqlite3_column_double(stmt: ?*sqlite3_stmt, idx: c_int) f64;
    pub extern fn sqlite3_column_text(stmt: ?*sqlite3_stmt, idx: c_int) [*]const u8;
};

pub const ColumnType = iface.ColumnType;
pub const Value = iface.Value;
pub const DbError = iface.DbError;

pub const SqliteDb = struct {
    handle: ?*c.sqlite3,
    gpa: std.mem.Allocator,

    pub fn open(gpa: std.mem.Allocator, path: [:0]const u8) DbError!SqliteDb {
        var raw_handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &raw_handle);
        if (rc != c.SQLITE_OK) {
            log.err("sqlite3_open failed for '{s}': rc={d}", .{ path, rc });
            return error.OpenFailed;
        }
        log.debug("opened database: {s}", .{path});
        return .{ .handle = raw_handle, .gpa = gpa };
    }

    pub fn close(self: *SqliteDb) void {
        if (self.handle) |h| {
            _ = c.sqlite3_close(h);
            self.handle = null;
            log.debug("closed database", .{});
        }
    }

    pub fn isOpen(self: *SqliteDb) bool {
        return self.handle != null;
    }

    pub fn exec(self: *SqliteDb, sql: [:0]const u8) DbError!void {
        const h = self.handle orelse return error.ExecFailed;
        const rc = c.sqlite3_exec(h, sql.ptr, null, null, null);
        if (rc == c.SQLITE_CONSTRAINT) return error.ConstraintViolation;
        if (rc != c.SQLITE_OK) {
            const msg = std.mem.sliceTo(c.sqlite3_errmsg(h), 0);
            log.err("exec failed: {s}", .{msg});
            return error.ExecFailed;
        }
        log.debug("exec: {s}", .{sql});
    }

    pub fn prepare(self: *SqliteDb, sql: [:0]const u8) DbError!SqliteStmt {
        const h = self.handle orelse return error.PrepareFailed;
        var raw_stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(h, sql.ptr, -1, &raw_stmt, null);
        if (rc != c.SQLITE_OK or raw_stmt == null) {
            const msg = std.mem.sliceTo(c.sqlite3_errmsg(h), 0);
            log.err("prepare failed: {s}", .{msg});
            return error.PrepareFailed;
        }
        log.debug("prepared: {s}", .{sql});
        return .{ .handle = raw_stmt.?, .db = self };
    }

    pub fn lastInsertRowId(self: *SqliteDb) i64 {
        const h = self.handle orelse return 0;
        return @intCast(c.sqlite3_last_insert_rowid(h));
    }

    pub fn changes(self: *SqliteDb) i64 {
        const h = self.handle orelse return 0;
        return @intCast(c.sqlite3_changes(h));
    }

    pub const dialect: iface.Dialect = iface.SqliteDialect;

    pub fn asRelationalDb(self: *SqliteDb) iface.RelationalDb {
        return .{ .ptr = @ptrCast(self), .vtable = &SQLITE_DB_VTABLE };
    }
};

const SQLITE_DB_VTABLE = iface.RelationalDb.VTable{
    .exec = sqliteDbExec,
    .prepare = sqliteDbPrepare,
    .lastInsertId = sqliteDbLastInsertId,
    .changes = sqliteDbChanges,
    .close = sqliteDbClose,
    .dialect = sqliteDbDialect,
};

fn sqliteDbExec(ptr: *anyopaque, sql: [:0]const u8) iface.DbError!void {
    const db: *SqliteDb = @ptrCast(@alignCast(ptr));
    try db.exec(sql);
}

fn sqliteDbPrepare(ptr: *anyopaque, sql: [:0]const u8) iface.DbError!iface.AnyStmt {
    const db: *SqliteDb = @ptrCast(@alignCast(ptr));
    const raw = try db.prepare(sql);
    const stmt = db.gpa.create(SqliteStmt) catch return error.AllocatorFailed;
    stmt.* = .{
        .handle = raw.handle,
        .db = raw.db,
        .allocated = true,
    };
    return stmt.asAnyStmt();
}

fn sqliteDbLastInsertId(ptr: *anyopaque) i64 {
    const db: *SqliteDb = @ptrCast(@alignCast(ptr));
    return db.lastInsertRowId();
}

fn sqliteDbChanges(ptr: *anyopaque) i64 {
    const db: *SqliteDb = @ptrCast(@alignCast(ptr));
    return db.changes();
}

fn sqliteDbClose(ptr: *anyopaque) void {
    const db: *SqliteDb = @ptrCast(@alignCast(ptr));
    db.close();
}

fn sqliteDbDialect(_: *anyopaque) iface.Dialect {
    return iface.SqliteDialect;
}

pub const SqliteStmt = struct {
    handle: *c.sqlite3_stmt,
    db: *SqliteDb,
    allocated: bool = false,

    pub fn finalize(self: *SqliteStmt) void {
        _ = c.sqlite3_finalize(self.handle);
        log.debug("finalized statement", .{});
    }

    pub fn reset(self: *SqliteStmt) DbError!void {
        const rc = c.sqlite3_reset(self.handle);
        if (rc != c.SQLITE_OK) return error.BindFailed;
    }

    pub fn bind(self: *SqliteStmt, value: Value, idx: c_int) DbError!void {
        const rc: c_int = switch (value) {
            .int => |n| c.sqlite3_bind_int64(self.handle, idx, @intCast(n)),
            .float => |f| c.sqlite3_bind_double(self.handle, idx, f),
            .text => |s| c.sqlite3_bind_text(self.handle, idx, s.ptr, @intCast(s.len), c.SQLITE_TRANSIENT),
            .null => c.sqlite3_bind_null(self.handle, idx),
        };
        if (rc != c.SQLITE_OK) {
            log.err("bind failed at index {d}: rc={d}", .{ idx, rc });
            return error.BindFailed;
        }
    }

    pub fn step(self: *SqliteStmt) DbError!bool {
        const rc = c.sqlite3_step(self.handle);
        if (rc == c.SQLITE_ROW) return true;
        if (rc == c.SQLITE_DONE) return false;
        if (rc == c.SQLITE_CONSTRAINT) return error.ConstraintViolation;
        const h = self.db.handle orelse return error.StepFailed;
        const msg = std.mem.sliceTo(c.sqlite3_errmsg(h), 0);
        log.err("step failed: {s}", .{msg});
        return error.StepFailed;
    }

    pub fn column(self: *SqliteStmt, kind: ColumnType, idx: c_int) DbError!Value {
        const col_type = c.sqlite3_column_type(self.handle, idx);
        switch (kind) {
            .integer => {
                if (col_type != c.SQLITE_INTEGER) return error.ColumnFailed;
                return .{ .int = @intCast(c.sqlite3_column_int64(self.handle, idx)) };
            },
            .float => {
                if (col_type != c.SQLITE_FLOAT and col_type != c.SQLITE_INTEGER) return error.ColumnFailed;
                return .{ .float = c.sqlite3_column_double(self.handle, idx) };
            },
            .text => {
                if (col_type != c.SQLITE_TEXT) return error.ColumnFailed;
                // Safe: sqlite3_column_text always returns a null-terminated string or NULL
                const ptr: [*:0]const u8 = @ptrCast(c.sqlite3_column_text(self.handle, idx));
                const len = std.mem.sliceTo(ptr, 0).len;
                return .{ .text = ptr[0..len] };
            },
            else => return error.ColumnFailed,
        }
    }

    pub fn columnType(self: *SqliteStmt, idx: c_int) DbError!ColumnType {
        return switch (c.sqlite3_column_type(self.handle, idx)) {
            c.SQLITE_INTEGER => .integer,
            c.SQLITE_FLOAT => .float,
            c.SQLITE_TEXT => .text,
            c.SQLITE_BLOB => .blob,
            c.SQLITE_NULL => .null,
            else => .null,
        };
    }

    pub fn asAnyStmt(self: *SqliteStmt) iface.AnyStmt {
        return .{ .ptr = @ptrCast(self), .vtable = &SQLITE_STMT_VTABLE };
    }
};

const SQLITE_STMT_VTABLE = iface.AnyStmt.VTable{
    .bind = sqliteStmtBind,
    .step = sqliteStmtStep,
    .column = sqliteStmtColumn,
    .columnType = sqliteStmtColumnType,
    .reset = sqliteStmtReset,
    .finalize = sqliteStmtFinalize,
};

fn sqliteStmtBind(ptr: *anyopaque, value: iface.Value, idx: c_int) iface.DbError!void {
    const stmt: *SqliteStmt = @ptrCast(@alignCast(ptr));
    try stmt.bind(value, idx);
}

fn sqliteStmtStep(ptr: *anyopaque) iface.DbError!bool {
    const stmt: *SqliteStmt = @ptrCast(@alignCast(ptr));
    return try stmt.step();
}

fn sqliteStmtColumn(ptr: *anyopaque, kind: iface.ColumnType, idx: c_int) iface.DbError!iface.Value {
    const stmt: *SqliteStmt = @ptrCast(@alignCast(ptr));
    return try stmt.column(kind, idx);
}

fn sqliteStmtColumnType(ptr: *anyopaque, idx: c_int) iface.DbError!iface.ColumnType {
    const stmt: *SqliteStmt = @ptrCast(@alignCast(ptr));
    return try stmt.columnType(idx);
}

fn sqliteStmtReset(ptr: *anyopaque) iface.DbError!void {
    const stmt: *SqliteStmt = @ptrCast(@alignCast(ptr));
    try stmt.reset();
}

fn sqliteStmtFinalize(ptr: *anyopaque) void {
    const stmt: *SqliteStmt = @ptrCast(@alignCast(ptr));
    stmt.finalize();
    if (stmt.allocated) stmt.db.gpa.destroy(stmt);
}

test {
    std.testing.refAllDecls(@This());
}
