/// zypher ORM — driver interface vtable types and SQL dialect definitions.
/// No C FFI here — pure Zig interface types.
const std = @import("std");
const log = std.log.scoped(.db_driver);

/// Value type used by all drivers for bind parameters and column results.
pub const Value = union(enum) {
    int: i64,
    float: f64,
    text: []const u8,
    null: void,
};

/// Column type enum used by all drivers.
pub const ColumnType = enum {
    integer,
    float,
    text,
    blob,
    null,
};

/// Database driver error set — superset covering all relational and non-relational drivers.
pub const DbError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    ColumnFailed,
    ConstraintViolation,
    UnexpectedResult,
    AllocatorFailed,
};

/// Vtable for a prepared statement. Wraps any driver's statement type.
pub const AnyStmt = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        bind: *const fn (ptr: *anyopaque, value: Value, idx: c_int) DbError!void,
        step: *const fn (ptr: *anyopaque) DbError!bool,
        column: *const fn (ptr: *anyopaque, kind: ColumnType, idx: c_int) DbError!Value,
        columnType: *const fn (ptr: *anyopaque, idx: c_int) DbError!ColumnType,
        reset: *const fn (ptr: *anyopaque) DbError!void,
        finalize: *const fn (ptr: *anyopaque) void,
    };

    pub fn bind(self: AnyStmt, value: Value, idx: c_int) DbError!void {
        try self.vtable.bind(self.ptr, value, idx);
    }

    pub fn step(self: AnyStmt) DbError!bool {
        return try self.vtable.step(self.ptr);
    }

    pub fn column(self: AnyStmt, kind: ColumnType, idx: c_int) DbError!Value {
        return try self.vtable.column(self.ptr, kind, idx);
    }

    pub fn columnType(self: AnyStmt, idx: c_int) DbError!ColumnType {
        return try self.vtable.columnType(self.ptr, idx);
    }

    pub fn reset(self: AnyStmt) DbError!void {
        try self.vtable.reset(self.ptr);
    }

    pub fn finalize(self: AnyStmt) void {
        self.vtable.finalize(self.ptr);
    }
};

/// Vtable for a relational database connection. Wraps any driver's Db type.
pub const RelationalDb = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        exec: *const fn (ptr: *anyopaque, sql: [:0]const u8) DbError!void,
        prepare: *const fn (ptr: *anyopaque, sql: [:0]const u8) DbError!AnyStmt,
        lastInsertId: *const fn (ptr: *anyopaque) i64,
        changes: *const fn (ptr: *anyopaque) i64,
        close: *const fn (ptr: *anyopaque) void,
        dialect: *const fn (ptr: *anyopaque) Dialect,
    };

    pub fn exec(self: RelationalDb, sql: [:0]const u8) DbError!void {
        try self.vtable.exec(self.ptr, sql);
    }

    pub fn prepare(self: RelationalDb, sql: [:0]const u8) DbError!AnyStmt {
        return try self.vtable.prepare(self.ptr, sql);
    }

    pub fn lastInsertId(self: RelationalDb) i64 {
        return self.vtable.lastInsertId(self.ptr);
    }

    pub fn changes(self: RelationalDb) i64 {
        return self.vtable.changes(self.ptr);
    }

    pub fn close(self: RelationalDb) void {
        self.vtable.close(self.ptr);
    }

    pub fn dialect(self: RelationalDb) Dialect {
        return self.vtable.dialect(self.ptr);
    }
};

/// SQL dialect properties that differ across relational databases.
/// Used by schema.zig to generate dialect-correct DDL and by query.zig for placeholder style.
pub const Dialect = struct {
    pk_type: []const u8,
    float_type: []const u8,
    bool_type: []const u8,
    text_type: []const u8,
    timestamp_now: []const u8,
    placeholder: *const fn (idx: usize, buf: *[16]u8) []const u8,
};

fn sqlitePlaceholder(idx: usize, buf: *[16]u8) []const u8 {
    _ = buf;
    _ = idx;
    return "?";
}

fn postgresPlaceholder(idx: usize, buf: *[16]u8) []const u8 {
    return std.fmt.bufPrint(buf, "${d}", .{idx}) catch "?";
}

fn mysqlPlaceholder(idx: usize, buf: *[16]u8) []const u8 {
    _ = buf;
    _ = idx;
    return "?";
}

pub const SqliteDialect: Dialect = .{
    .pk_type = "INTEGER PRIMARY KEY AUTOINCREMENT",
    .float_type = "REAL",
    .bool_type = "INTEGER",
    .text_type = "TEXT",
    .timestamp_now = "strftime('%s','now')",
    .placeholder = sqlitePlaceholder,
};

pub const PostgresDialect: Dialect = .{
    .pk_type = "BIGSERIAL PRIMARY KEY",
    .float_type = "DOUBLE PRECISION",
    .bool_type = "BOOLEAN",
    .text_type = "TEXT",
    .timestamp_now = "EXTRACT(EPOCH FROM NOW())::BIGINT",
    .placeholder = postgresPlaceholder,
};

pub const MysqlDialect: Dialect = .{
    .pk_type = "INT AUTO_INCREMENT PRIMARY KEY",
    .float_type = "DOUBLE",
    .bool_type = "TINYINT(1)",
    .text_type = "TEXT",
    .timestamp_now = "UNIX_TIMESTAMP()",
    .placeholder = mysqlPlaceholder,
};

test {
    std.testing.refAllDecls(@This());
}
