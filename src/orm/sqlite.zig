/// zypher ORM — SQLite backward-compat re-export shim.
/// Delegates to src/orm/driver/sqlite.zig.
/// Existing callers (query.zig, migration.zig, etc.) continue to compile without changes.
const std = @import("std");

pub const driver = @import("driver/sqlite.zig");

pub const Db = driver.SqliteDb;
pub const Stmt = driver.SqliteStmt;
pub const Value = driver.Value;
pub const ColumnType = driver.ColumnType;
pub const DbError = driver.DbError;

test {
    std.testing.refAllDecls(@This());
}
