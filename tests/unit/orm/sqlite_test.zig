const std = @import("std");
const sqlite = @import("zypher").orm.sqlite;

const Db = sqlite.Db;
const Stmt = sqlite.Stmt;

test "sqlite: open in-memory database" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();
    try std.testing.expect(db.isOpen());
}

test "sqlite: close database" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    db.close();
    try std.testing.expect(!db.isOpen());
}

test "sqlite: execute DDL statement" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER)");
}

test "sqlite: execute parameterised INSERT" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER)");

    var stmt = try db.prepare("INSERT INTO users (name, age) VALUES (?, ?)");
    defer stmt.finalize();

    try stmt.bind(.{ .text = "Alice" }, 1);
    try stmt.bind(.{ .int = 30 }, 2);
    _ = try stmt.step();

    try stmt.reset();
    try stmt.bind(.{ .text = "Bob" }, 1);
    try stmt.bind(.{ .int = 25 }, 2);
    _ = try stmt.step();
}

test "sqlite: execute SELECT and read columns" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER)");

    // Insert a row
    var ins = try db.prepare("INSERT INTO users (name, age) VALUES (?, ?)");
    defer ins.finalize();
    try ins.bind(.{ .text = "Alice" }, 1);
    try ins.bind(.{ .int = 30 }, 2);
    _ = try ins.step();

    // Select it back
    var sel = try db.prepare("SELECT id, name, age FROM users WHERE name = ?");
    defer sel.finalize();
    try sel.bind(.{ .text = "Alice" }, 1);

    const has_row = try sel.step();
    try std.testing.expect(has_row);

    const id = try sel.column(.integer, 0);
    try std.testing.expectEqual(sqlite.Value{ .int = 1 }, id);

    const name = try sel.column(.text, 1);
    try std.testing.expectEqualStrings("Alice", name.text);

    const age = try sel.column(.integer, 2);
    try std.testing.expectEqual(sqlite.Value{ .int = 30 }, age);

    // No more rows
    const has_more = try sel.step();
    try std.testing.expect(!has_more);
}

test "sqlite: bind double and null values" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE metrics (id INTEGER PRIMARY KEY, value REAL, note TEXT)");

    var ins = try db.prepare("INSERT INTO metrics (value, note) VALUES (?, ?)");
    defer ins.finalize();
    try ins.bind(.{ .float = 3.14 }, 1);
    try ins.bind(.null, 2);
    _ = try ins.step();

    var sel = try db.prepare("SELECT value, note FROM metrics");
    defer sel.finalize();
    const has_row = try sel.step();
    try std.testing.expect(has_row);

    const val = try sel.column(.float, 0);
    try std.testing.expect(std.math.approxEqAbs(f64, val.float, 3.14, 0.001));

    const note_type = try sel.columnType(1);
    try std.testing.expectEqual(sqlite.ColumnType.null, note_type);
}

test "sqlite: error on constraint violation" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");

    var stmt = try db.prepare("INSERT INTO items (name) VALUES (?)");
    defer stmt.finalize();
    try stmt.bind(.null, 1);

    const result = stmt.step();
    try std.testing.expectError(error.ConstraintViolation, result);
}

test "sqlite: last insert rowid" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)");

    var ins = try db.prepare("INSERT INTO items (name) VALUES (?)");
    defer ins.finalize();
    try ins.bind(.{ .text = "first" }, 1);
    _ = try ins.step();

    try std.testing.expectEqual(@as(i64, 1), db.lastInsertRowId());
}

test "sqlite: changes count after UPDATE" {
    const gpa = std.testing.allocator;
    var db = try Db.open(gpa, ":memory:");
    defer db.close();

    try db.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)");
    try db.exec("INSERT INTO items (name) VALUES ('a')");
    try db.exec("INSERT INTO items (name) VALUES ('b')");

    try db.exec("UPDATE items SET name = 'x' WHERE id > 0");
    try std.testing.expectEqual(@as(i64, 2), db.changes());
}
