/// Integration test: Database Configuration API end-to-end.
/// Opens a real SQLite database via openDatabase, exercises the
/// RelationalDb vtable, and verifies cleanup.
const std = @import("std");
const zypher = @import("zypher");

const config = zypher.orm.config;

test "database config: open sqlite, exec, prepare, step, close" {
    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    try db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)");

    var stmt = try db.prepare("INSERT INTO test (val) VALUES (?)");
    defer stmt.finalize();
    try stmt.bind(.{ .text = "hello" }, 1);
    _ = try stmt.step();

    var stmt2 = try db.prepare("SELECT val FROM test WHERE id = ?");
    defer stmt2.finalize();
    try stmt2.bind(.{ .int = 1 }, 1);
    try std.testing.expect(try stmt2.step());
    const val = try stmt2.column(.text, 0);
    try std.testing.expectEqualStrings("hello", val.text);
}

test "database config: open sqlite with custom path and exec multiple" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fmt.allocPrintSentinel(std.testing.allocator, ".zig-cache/tmp/{s}/config_test.db", .{tmp.sub_path}, 0);
    defer std.testing.allocator.free(db_path);

    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = db_path } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    try db.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, count INTEGER)");
    try db.exec("INSERT INTO items (name, count) VALUES ('foo', 10)");
    try db.exec("INSERT INTO items (name, count) VALUES ('bar', 20)");

    var stmt = try db.prepare("SELECT COUNT(*) FROM items");
    defer stmt.finalize();
    try std.testing.expect(try stmt.step());
    const count = try stmt.column(.integer, 0);
    try std.testing.expectEqual(@as(i64, 2), count.int);
}

test "database config: driver not enabled for postgres" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.DriverNotEnabled, config.openDatabase(gpa, .{ .postgres = .{ .connstr = "postgresql://localhost/test" } }));
}

test "database config: driver not enabled for mysql" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.DriverNotEnabled, config.openDatabase(gpa, .{ .mysql = .{ .db = "test" } }));
}

test "database config: driver not enabled for mongodb" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.DriverNotEnabled, config.openDatabase(gpa, .{ .mongo = .{ .uri = "mongodb://localhost:27017", .default_db = "test" } }));
}

test "database config: driver not enabled for redis" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.DriverNotEnabled, config.openDatabase(gpa, .{ .redis = .{ .host = "127.0.0.1" } }));
}
