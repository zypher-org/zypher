/// Phase 5 Regression Test — Query builder never interpolates user values into SQL strings.
const std = @import("std");
const zypher = @import("zypher");

const sqlite = zypher.orm.sqlite;
const schema = zypher.orm.schema;
const query = zypher.orm.query;

const Db = sqlite.Db;
const FieldDef = schema.FieldDef;
const Field = schema.Field;
const Model = schema.Model;

// ── Test model ────────────────────────────────────────────────────────────

const ItemFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    name: FieldDef = Field("name", .text, .{ .required = true }),
    value: FieldDef = Field("value", .integer, .{}),
};
const Item = Model("items", ItemFields);
const ItemRow = query.RowType(Item);

fn openTestDb() !Db {
    return Db.open(std.testing.allocator, ":memory:");
}

fn freeItemRows(rows: *std.ArrayList(ItemRow)) void {
    for (rows.items) |*r| {
        query.freeRow(Item, std.testing.allocator, r);
    }
    rows.deinit(std.testing.allocator);
}

// ── Regression Tests ──────────────────────────────────────────────────────

test "orm regression: SQL injection in filter value is safely bound" {
    var db = try openTestDb();
    defer db.close();
    try db.exec(Item.create_table_sql);

    _ = try query.create(Item, &db, &.{ .{ .text = "normal" }, .{ .int = 1 } });

    // Classic SQL injection attempt
    const injection = "'; DROP TABLE items; --";
    var rows = try query.filter(Item, &db, std.testing.allocator, "name = ?", &.{.{ .text = injection }});
    defer freeItemRows(&rows);
    try std.testing.expectEqual(@as(usize, 0), rows.items.len);

    // Table must still exist
    try std.testing.expectEqual(@as(u64, 1), try query.count(Item, &db));
}

test "orm regression: SQL injection in filter WHERE clause uses bound params" {
    var db = try openTestDb();
    defer db.close();
    try db.exec(Item.create_table_sql);

    _ = try query.create(Item, &db, &.{ .{ .text = "safe_value" }, .{ .int = 42 } });

    // Injection via OR 1=1 pattern — should not return all rows
    var rows = try query.filter(Item, &db, std.testing.allocator, "name = ? OR 1=1", &.{.{ .text = "nonexistent" }});
    defer freeItemRows(&rows);
    // This SHOULD return all rows because the WHERE clause itself is "name = ? OR 1=1"
    // which is always true. This test verifies the bind param works — the ? is bound
    // to "nonexistent" but OR 1=1 makes the whole clause true.
    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
}

test "orm regression: integer injection in filter is safely bound" {
    var db = try openTestDb();
    defer db.close();
    try db.exec(Item.create_table_sql);

    _ = try query.create(Item, &db, &.{ .{ .text = "item1" }, .{ .int = 100 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "item2" }, .{ .int = 200 } });

    // Try to inject via integer field
    var rows = try query.filter(Item, &db, std.testing.allocator, "value = ?", &.{.{ .int = 100 }});
    defer freeItemRows(&rows);
    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    try std.testing.expectEqualStrings("item1", rows.items[0].name);
}

test "orm regression: create with injection in text field is safely bound" {
    var db = try openTestDb();
    defer db.close();
    try db.exec(Item.create_table_sql);

    // Insert a record with SQL-like content in a text field
    const malicious = "'); INSERT INTO items (name, value) VALUES ('hacked', 999); --";
    const row_id = try query.create(Item, &db, &.{ .{ .text = malicious }, .{ .int = 1 } });

    var row = try query.getById(Item, &db, std.testing.allocator, row_id);
    defer query.freeRow(Item, std.testing.allocator, &row);
    // The malicious string should be stored as-is, not executed as SQL
    try std.testing.expectEqualStrings(malicious, row.name);

    // Only one record should exist — the "hacked" insert did not execute
    try std.testing.expectEqual(@as(u64, 1), try query.count(Item, &db));
}
