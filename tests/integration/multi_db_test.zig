const std = @import("std");
const zypher = @import("zypher");
const testIo = @import("test_io").testIo;

const config = zypher.orm.config;
const schema = zypher.orm.schema;
const query = zypher.orm.query;
const migration = zypher.orm.migration;
const RelationalDb = zypher.orm.RelationalDb;
const ColumnType = zypher.orm.driver.interface.ColumnType;

const ItemFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    name: schema.FieldDef = schema.Field("name", .text, .{}),
    value: schema.FieldDef = schema.Field("value", .integer, .{}),
    active: schema.FieldDef = schema.Field("active", .boolean, .{}),
};
const Item = schema.Model("integration_items", ItemFields);

test "multi-db: full ORM CRUD via RelationalDb" {
    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    try db.exec(Item.create_table_sql);

    const id1 = try query.create(Item, db, &.{
        .{ .text = "alpha" },
        .{ .int = 10 },
        .{ .int = 1 },
    });
    try std.testing.expectEqual(@as(i64, 1), id1);

    const id2 = try query.create(Item, db, &.{
        .{ .text = "beta" },
        .{ .int = 20 },
        .{ .int = 0 },
    });
    try std.testing.expectEqual(@as(i64, 2), id2);

    {
        var row = try query.getById(Item, db, gpa, 1);
        defer query.freeRow(Item, gpa, &row);
        try std.testing.expectEqualStrings("alpha", row[1]);
        try std.testing.expectEqual(@as(i64, 10), row[2]);
        try std.testing.expectEqual(true, row[3]);
    }

    {
        var all = try query.all(Item, db, gpa);
        defer {
            for (all.items) |*r| query.freeRow(Item, gpa, r);
            all.deinit(gpa);
        }
        try std.testing.expectEqual(@as(usize, 2), all.items.len);
    }

    try query.updateById(Item, db, 1, &.{
        .{ .text = "alpha-updated" },
        .{ .int = 15 },
        .{ .int = 1 },
    });

    {
        var row = try query.getById(Item, db, gpa, 1);
        defer query.freeRow(Item, gpa, &row);
        try std.testing.expectEqualStrings("alpha-updated", row[1]);
        try std.testing.expectEqual(@as(i64, 15), row[2]);
    }

    try query.deleteById(Item, db, 2);

    {
        var all = try query.all(Item, db, gpa);
        defer {
            for (all.items) |*r| query.freeRow(Item, gpa, r);
            all.deinit(gpa);
        }
        try std.testing.expectEqual(@as(usize, 1), all.items.len);
    }
}

test "multi-db: query builder filter/order/limit/offset" {
    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    try db.exec(Item.create_table_sql);

    const names = [_][]const u8{ "delta", "charlie", "bravo", "alpha" };
    for (names, 0..) |name, i| {
        const val: i64 = @intCast((i + 1) * 10);
        const act: i64 = if (i % 2 == 0) 1 else 0;
        _ = try query.create(Item, db, &.{
            .{ .text = name },
            .{ .int = val },
            .{ .int = act },
        });
    }

    {
        var qs = query.QuerySet(Item).init(db, gpa);
        defer qs.deinit();
        var rows = try qs.filterBy("name LIKE ?", &.{.{ .text = "%a%" }}).orderBy("value ASC").exec();
        defer {
            for (rows.items) |*r| query.freeRow(Item, gpa, r);
            rows.deinit(gpa);
        }
        try std.testing.expectEqual(@as(usize, 4), rows.items.len);
        try std.testing.expectEqualStrings("delta", rows.items[0][1]);
    }

    {
        var qs = query.QuerySet(Item).init(db, gpa);
        defer qs.deinit();
        var rows = try qs.filterBy("active = ?", &.{.{ .int = 1 }}).orderBy("id ASC").exec();
        defer {
            for (rows.items) |*r| query.freeRow(Item, gpa, r);
            rows.deinit(gpa);
        }
        try std.testing.expectEqual(@as(usize, 2), rows.items.len);
        try std.testing.expectEqualStrings("delta", rows.items[0][1]);
        try std.testing.expectEqualStrings("bravo", rows.items[1][1]);
    }

    {
        var qs = query.QuerySet(Item).init(db, gpa);
        defer qs.deinit();
        var rows = try qs.filterBy("active = ?", &.{.{ .int = 1 }}).orderBy("value ASC").limit(1).offset(1).exec();
        defer {
            for (rows.items) |*r| query.freeRow(Item, gpa, r);
            rows.deinit(gpa);
        }
        try std.testing.expectEqual(@as(usize, 1), rows.items.len);
        try std.testing.expectEqualStrings("bravo", rows.items[0][1]);
    }
}

test "multi-db: migration runner via RelationalDb" {
    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    var runner = migration.MigrationRunner.init(db);

    try runner.ensureHistoryTable();

    const m1 = migration.Migration{
        .id = 1,
        .name = "create_items",
        .up_sql = Item.create_table_sql,
        .down_sql = "DROP TABLE IF EXISTS integration_items",
    };

    const m2 = migration.Migration{
        .id = 2,
        .name = "add_description",
        .up_sql = "ALTER TABLE integration_items ADD COLUMN description TEXT DEFAULT ''",
        .down_sql = "ALTER TABLE integration_items DROP COLUMN description",
    };

    {
        const count = try runner.countApplied();
        try std.testing.expectEqual(@as(u64, 0), count);
    }

    try runner.migrate(&.{ m1, m2 }, testIo());

    {
        const count = try runner.countApplied();
        try std.testing.expectEqual(@as(u64, 2), count);
    }

    try runner.migrate(&.{ m1, m2 }, testIo());

    {
        const count = try runner.countApplied();
        try std.testing.expectEqual(@as(u64, 2), count);
    }

    {
        const status = try runner.status(gpa, &.{ m1, m2 });
        defer gpa.free(status);
        try std.testing.expectEqual(@as(usize, 2), status.len);
        for (status) |s| {
            try std.testing.expect(s.applied);
        }
    }

    try runner.rollback(&.{ m1, m2 }, 1);

    {
        const count = try runner.countApplied();
        try std.testing.expectEqual(@as(u64, 1), count);
    }

    try runner.rollback(&.{ m1, m2 }, 1);

    {
        const count = try runner.countApplied();
        try std.testing.expectEqual(@as(u64, 0), count);
    }
}

test "multi-db: null value round-trip" {
    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    try db.exec("CREATE TABLE null_test (id INTEGER PRIMARY KEY, name TEXT, score INTEGER)");

    try db.exec("INSERT INTO null_test (name, score) VALUES ('has_val', 42)");
    try db.exec("INSERT INTO null_test (name, score) VALUES (NULL, NULL)");

    var stmt = try db.prepare("SELECT name, score FROM null_test WHERE id = ?");
    defer stmt.finalize();
    try stmt.bind(.{ .int = 2 }, 1);
    try std.testing.expect(try stmt.step());

    {
        const ctype0 = try stmt.columnType(0);
        try std.testing.expectEqual(ColumnType.null, ctype0);
        const ctype1 = try stmt.columnType(1);
        try std.testing.expectEqual(ColumnType.null, ctype1);
    }
}

test "multi-db: error paths — constraint violation" {
    const gpa = std.testing.allocator;

    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational orelse return error.NoRelationalDb;

    try db.exec("CREATE TABLE uniq_test (id INTEGER PRIMARY KEY, name TEXT UNIQUE)");

    try db.exec("INSERT INTO uniq_test (name) VALUES ('first')");

    const err = db.exec("INSERT INTO uniq_test (name) VALUES ('first')");
    try std.testing.expectError(error.ConstraintViolation, err);
}

test "multi-db: App.useDatabase round-trip" {
    const gpa = std.testing.allocator;

    var app = zypher.core.App.init(gpa, .{});
    defer app.deinit();

    try app.useDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });

    const db = try app.db();
    try db.exec(Item.create_table_sql);

    _ = try query.create(Item, db, &.{
        .{ .text = "app-test" },
        .{ .int = 99 },
        .{ .int = 1 },
    });

    {
        var all = try query.all(Item, db, gpa);
        defer {
            for (all.items) |*r| query.freeRow(Item, gpa, r);
            all.deinit(gpa);
        }
        try std.testing.expectEqual(@as(usize, 1), all.items.len);
        try std.testing.expectEqualStrings("app-test", all.items[0][1]);
    }

    {
        const ds = app.documentStore();
        try std.testing.expectError(error.WrongStoreType, ds);
    }

    {
        const ks = app.kvStore();
        try std.testing.expectError(error.WrongStoreType, ks);
    }
}

test "multi-db: App.useDatabase document store type error" {
    const gpa = std.testing.allocator;

    var app = zypher.core.App.init(gpa, .{});
    defer app.deinit();

    try app.useDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });

    const ds = app.documentStore();
    try std.testing.expectError(error.WrongStoreType, ds);
}

test "multi-db: App.db() before useDatabase returns NoDatabaseConfigured" {
    const gpa = std.testing.allocator;
    var app = zypher.core.App.init(gpa, .{});
    defer app.deinit();

    const err = app.db();
    try std.testing.expectError(error.NoDatabaseConfigured, err);
}
