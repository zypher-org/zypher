const std = @import("std");
const schema = @import("zypher").orm.schema;
const sqlite = @import("zypher").orm.sqlite;
const query = @import("zypher").orm.query;

const FieldDef = schema.FieldDef;
const Field = schema.Field;
const Model = schema.Model;
const Db = sqlite.Db;
const Value = sqlite.Value;

// ── Test model ────────────────────────────────────────────────────────────

const ItemFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    name: FieldDef = Field("name", .text, .{ .required = true }),
    value: FieldDef = Field("value", .integer, .{}),
};
const Item = Model("items", ItemFields);
const ItemRow = query.RowType(Item);

// ── Helpers ───────────────────────────────────────────────────────────────

fn openTestDb() !Db {
    return Db.open(std.testing.allocator, ":memory:");
}

fn createItemsTable(db: *Db) !void {
    try db.exec(Item.create_table_sql);
}

fn freeItemRows(rows: *std.ArrayList(ItemRow)) void {
    for (rows.items) |*r| {
        query.freeRow(Item, std.testing.allocator, r);
    }
    rows.deinit(std.testing.allocator);
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "query: create and retrieve a record" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    const row_id = try query.create(Item, &db, &.{
        .{ .text = "alpha" },
        .{ .int = 10 },
    });
    try std.testing.expect(row_id > 0);

    var stmt = try db.prepare(Item.select_by_id_sql);
    defer stmt.finalize();
    try stmt.bind(.{ .int = row_id }, 1);

    const has_row = try stmt.step();
    try std.testing.expect(has_row);

    const name_val = try stmt.column(.text, 1);
    try std.testing.expectEqualStrings("alpha", name_val.text);

    const value_val = try stmt.column(.integer, 2);
    try std.testing.expectEqual(@as(i64, 10), value_val.int);
}

test "query: get by id returns record" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    const row_id = try query.create(Item, &db, &.{
        .{ .text = "beta" },
        .{ .int = 20 },
    });

    var row = try query.getById(Item, &db, std.testing.allocator, row_id);
    defer query.freeRow(Item, std.testing.allocator, &row);
    try std.testing.expectEqual(row_id, row.id);
    try std.testing.expectEqualStrings("beta", row.name);
    try std.testing.expectEqual(@as(i64, 20), row.value);
}

test "query: get by id returns NotFound for missing record" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    const result = query.getById(Item, &db, std.testing.allocator, 9999);
    try std.testing.expectError(error.NotFound, result);
}

test "query: all returns all records" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    _ = try query.create(Item, &db, &.{ .{ .text = "a" }, .{ .int = 1 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "b" }, .{ .int = 2 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "c" }, .{ .int = 3 } });

    var rows = try query.all(Item, &db, std.testing.allocator);
    defer freeItemRows(&rows);
    try std.testing.expectEqual(@as(usize, 3), rows.items.len);
}

test "query: updateById modifies a record" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    const row_id = try query.create(Item, &db, &.{
        .{ .text = "original" },
        .{ .int = 100 },
    });

    try query.updateById(Item, &db, row_id, &.{
        .{ .text = "updated" },
        .{ .int = 200 },
    });

    var row = try query.getById(Item, &db, std.testing.allocator, row_id);
    defer query.freeRow(Item, std.testing.allocator, &row);
    try std.testing.expectEqualStrings("updated", row.name);
    try std.testing.expectEqual(@as(i64, 200), row.value);
}

test "query: deleteById removes a record" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    const row_id = try query.create(Item, &db, &.{
        .{ .text = "doomed" },
        .{ .int = 0 },
    });

    try query.deleteById(Item, &db, row_id);

    const result = query.getById(Item, &db, std.testing.allocator, row_id);
    try std.testing.expectError(error.NotFound, result);
}

test "query: count returns number of records" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    try std.testing.expectEqual(@as(u64, 0), try query.count(Item, &db));

    _ = try query.create(Item, &db, &.{ .{ .text = "x" }, .{ .int = 1 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "y" }, .{ .int = 2 } });

    try std.testing.expectEqual(@as(u64, 2), try query.count(Item, &db));
}

test "query: filter with WHERE clause" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    _ = try query.create(Item, &db, &.{ .{ .text = "foo" }, .{ .int = 1 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "bar" }, .{ .int = 2 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "foo" }, .{ .int = 3 } });

    var rows = try query.filter(Item, &db, std.testing.allocator, "name = ?", &.{.{ .text = "foo" }});
    defer freeItemRows(&rows);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
}

test "query: filter with LIMIT and OFFSET" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    _ = try query.create(Item, &db, &.{ .{ .text = "a" }, .{ .int = 1 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "b" }, .{ .int = 2 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "c" }, .{ .int = 3 } });
    _ = try query.create(Item, &db, &.{ .{ .text = "d" }, .{ .int = 4 } });

    var rows = try query.filterLimitOffset(Item, &db, std.testing.allocator, "", &.{}, 2, 1);
    defer freeItemRows(&rows);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    try std.testing.expectEqualStrings("b", rows.items[0].name);
    try std.testing.expectEqualStrings("c", rows.items[1].name);
}

test "query: SQL injection is safely bound, not injected" {
    var db = try openTestDb();
    defer db.close();
    try createItemsTable(&db);

    _ = try query.create(Item, &db, &.{ .{ .text = "normal" }, .{ .int = 1 } });

    const injection = "'; DROP TABLE items; --";
    var rows = try query.filter(Item, &db, std.testing.allocator, "name = ?", &.{.{ .text = injection }});
    defer freeItemRows(&rows);
    try std.testing.expectEqual(@as(usize, 0), rows.items.len);

    // Verify table still exists by counting
    try std.testing.expectEqual(@as(u64, 1), try query.count(Item, &db));
}
