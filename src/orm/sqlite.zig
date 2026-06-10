/// zypher ORM — thin SQLite3 C FFI wrapper.
/// Manual extern declarations (Zig 0.17 removed @cImport).
const std = @import("std");

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

// ── Public types ──────────────────────────────────────────────────────────

pub const ColumnType = enum {
    integer,
    float,
    text,
    blob,
    null,
};

pub const Value = union(enum) {
    int: i64,
    float: f64,
    text: []const u8,
    null: void,
};

pub const DbError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    ColumnFailed,
    ConstraintViolation,
    UnexpectedResult,
};

// ── Db ────────────────────────────────────────────────────────────────────

pub const Db = struct {
    handle: ?*c.sqlite3,
    gpa: std.mem.Allocator,

    /// Open a database connection. Use ":memory:" for in-memory databases.
    pub fn open(gpa: std.mem.Allocator, path: [:0]const u8) DbError!Db {
        var raw_handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &raw_handle);
        if (rc != c.SQLITE_OK) {
            log.err("sqlite3_open failed for '{s}': rc={d}", .{ path, rc });
            return error.OpenFailed;
        }
        log.debug("opened database: {s}", .{path});
        return .{ .handle = raw_handle, .gpa = gpa };
    }

    /// Close the database connection.
    pub fn close(self: *Db) void {
        if (self.handle) |h| {
            _ = c.sqlite3_close(h);
            self.handle = null;
            log.debug("closed database", .{});
        }
    }

    /// Check if the database connection is open.
    pub fn isOpen(self: *Db) bool {
        return self.handle != null;
    }

    /// Execute a SQL statement (no parameters, no result rows).
    pub fn exec(self: *Db, sql: [:0]const u8) DbError!void {
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

    /// Prepare a SQL statement for parameterised execution.
    pub fn prepare(self: *Db, sql: [:0]const u8) DbError!Stmt {
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

    /// Get the rowid of the last INSERT.
    pub fn lastInsertRowId(self: *Db) i64 {
        const h = self.handle orelse return 0;
        return @intCast(c.sqlite3_last_insert_rowid(h));
    }

    /// Get the number of rows changed by the last UPDATE/DELETE.
    pub fn changes(self: *Db) i64 {
        const h = self.handle orelse return 0;
        return @intCast(c.sqlite3_changes(h));
    }
};

// ── Stmt ──────────────────────────────────────────────────────────────────

pub const Stmt = struct {
    handle: *c.sqlite3_stmt,
    db: *Db,

    /// Finalize the prepared statement, freeing resources.
    pub fn finalize(self: *Stmt) void {
        _ = c.sqlite3_finalize(self.handle);
        log.debug("finalized statement", .{});
    }

    /// Reset the prepared statement so it can be re-executed.
    pub fn reset(self: *Stmt) DbError!void {
        const rc = c.sqlite3_reset(self.handle);
        if (rc != c.SQLITE_OK) return error.BindFailed;
    }

    /// Bind a value to a parameter by 1-based index.
    pub fn bind(self: *Stmt, value: Value, idx: c_int) DbError!void {
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

    /// Step to the next row. Returns true if a row is available, false if done.
    /// Returns error on constraint violation or other errors.
    pub fn step(self: *Stmt) DbError!bool {
        const rc = c.sqlite3_step(self.handle);
        if (rc == c.SQLITE_ROW) return true;
        if (rc == c.SQLITE_DONE) return false;
        if (rc == c.SQLITE_CONSTRAINT) return error.ConstraintViolation;
        const h = self.db.handle orelse return error.StepFailed;
        const msg = std.mem.sliceTo(c.sqlite3_errmsg(h), 0);
        log.err("step failed: {s}", .{msg});
        return error.StepFailed;
    }

    /// Read a column value from the current row.
    pub fn column(self: *Stmt, kind: ColumnType, idx: c_int) DbError!Value {
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
                const ptr: [*:0]const u8 = @ptrCast(c.sqlite3_column_text(self.handle, idx));
                const len = std.mem.sliceTo(ptr, 0).len;
                return .{ .text = ptr[0..len] };
            },
            else => return error.ColumnFailed,
        }
    }

    /// Get the type of a column in the current row.
    pub fn columnType(self: *Stmt, idx: c_int) DbError!ColumnType {
        return switch (c.sqlite3_column_type(self.handle, idx)) {
            c.SQLITE_INTEGER => .integer,
            c.SQLITE_FLOAT => .float,
            c.SQLITE_TEXT => .text,
            c.SQLITE_BLOB => .blob,
            c.SQLITE_NULL => .null,
            else => .null,
        };
    }
};

test {
    std.testing.refAllDecls(@This());
}
