const std = @import("std");
const test_io = @import("test_io");
const sqlite_driver = @import("zypher").orm.driver.sqlite;
const iface = @import("zypher").orm.driver.interface;

test "SqliteDb.asRelationalDb() returns valid RelationalDb — exec through vtable" {
    var db = try sqlite_driver.SqliteDb.open(std.testing.allocator, ":memory:");
    defer db.close();

    var rdb = db.asRelationalDb();
    try rdb.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)");

    var stmt = try rdb.prepare("INSERT INTO test (val) VALUES (?)");
    defer stmt.finalize();
    try stmt.bind(.{ .text = "hello" }, 1);
    _ = try stmt.step();
}

test "SqliteDb.asRelationalDb() — insert + select through vtable" {
    var db = try sqlite_driver.SqliteDb.open(std.testing.allocator, ":memory:");
    defer db.close();

    var rdb = db.asRelationalDb();
    try rdb.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)");

    var ins = try rdb.prepare("INSERT INTO test (val) VALUES (?)");
    defer ins.finalize();
    try ins.bind(.{ .text = "world" }, 1);
    _ = try ins.step();

    const inserted_id = rdb.lastInsertId();
    try std.testing.expectEqual(@as(i64, 1), inserted_id);

    var sel = try rdb.prepare("SELECT val FROM test WHERE id = ?");
    defer sel.finalize();
    try sel.bind(.{ .int = inserted_id }, 1);
    try std.testing.expect(try sel.step());
    const val = try sel.column(.text, 0);
    try std.testing.expectEqualStrings("world", val.text);
}

test "SqliteDb.dialect returns correct SQLite dialect" {
    var db = try sqlite_driver.SqliteDb.open(std.testing.allocator, ":memory:");
    defer db.close();

    var rdb = db.asRelationalDb();
    const d = rdb.dialect();
    try std.testing.expectEqualStrings("INTEGER PRIMARY KEY AUTOINCREMENT", d.pk_type);
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("?", d.placeholder(1, &buf));
}

test "SqliteStmt.asAnyStmt() — bind, step, column through vtable" {
    var db = try sqlite_driver.SqliteDb.open(std.testing.allocator, ":memory:");
    defer db.close();
    try db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)");

    var raw_stmt = try db.prepare("INSERT INTO t (name) VALUES (?)");
    var stmt = raw_stmt.asAnyStmt();
    try stmt.bind(.{ .text = "via vtable" }, 1);
    _ = try stmt.step();
    stmt.finalize();

    var sel = try db.prepare("SELECT id, name FROM t");
    var any_sel = sel.asAnyStmt();
    try std.testing.expect(try any_sel.step());
    const id = try any_sel.column(.integer, 0);
    try std.testing.expectEqual(@as(i64, 1), id.int);
    const name = try any_sel.column(.text, 1);
    try std.testing.expectEqualStrings("via vtable", name.text);
    any_sel.finalize();
}
