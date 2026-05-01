/// Phase 5 Integration Test — Define model, run migration, CRUD records, confirm SQL correctness.
const std = @import("std");
const zypher = @import("zypher");

const sqlite = zypher.orm.sqlite;
const schema = zypher.orm.schema;
const query = zypher.orm.query;
const migration = zypher.orm.migration;

const Db = sqlite.Db;
const FieldDef = schema.FieldDef;
const Field = schema.Field;
const Model = schema.Model;
const Migration = migration.Migration;
const MigrationRunner = migration.MigrationRunner;

// ── Test model: User ─────────────────────────────────────────────────────

const UserFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    email: FieldDef = Field("email", .text, .{ .required = true, .unique = true }),
    name: FieldDef = Field("name", .text, .{ .required = true }),
    age: FieldDef = Field("age", .integer, .{}),
    active: FieldDef = Field("active", .boolean, .{ .default = .{ .boolean = true } }),
};
const User = Model("users", UserFields);
const UserRow = query.RowType(User);

// ── Helpers ───────────────────────────────────────────────────────────────

fn openTestDb() !Db {
    return Db.open(std.testing.allocator, ":memory:");
}

fn freeUserRows(rows: *std.ArrayList(UserRow)) void {
    for (rows.items) |*r| {
        query.freeRow(User, std.testing.allocator, r);
    }
    rows.deinit(std.testing.allocator);
}

// ── Integration Tests ─────────────────────────────────────────────────────

test "orm integration: full lifecycle — migrate, create, read, update, delete" {
    var db = try openTestDb();
    defer db.close();

    // 1. Run migration to create the users table
    var runner = MigrationRunner.init(&db);
    const migrations = [_]Migration{
        .{ .id = 1, .name = "create_users", .up_sql = User.create_table_sql, .down_sql = User.drop_table_sql },
    };
    try runner.migrate(&migrations);

    // 2. Create a user
    const row_id = try query.create(User, &db, &.{
        .{ .text = "alice@example.com" },
        .{ .text = "Alice" },
        .{ .int = 30 },
        .{ .int = 1 }, // active = true (stored as integer)
    });
    try std.testing.expect(row_id > 0);

    // 3. Read the user back by ID
    var row = try query.getById(User, &db, std.testing.allocator, row_id);
    defer query.freeRow(User, std.testing.allocator, &row);
    try std.testing.expectEqual(row_id, row.id);
    try std.testing.expectEqualStrings("alice@example.com", row.email);
    try std.testing.expectEqualStrings("Alice", row.name);
    try std.testing.expectEqual(@as(i64, 30), row.age);
    try std.testing.expect(row.active);

    // 4. Update the user
    try query.updateById(User, &db, row_id, &.{
        .{ .text = "alice.new@example.com" },
        .{ .text = "Alice Updated" },
        .{ .int = 31 },
        .{ .int = 0 }, // active = false
    });

    // 5. Verify the update
    var updated = try query.getById(User, &db, std.testing.allocator, row_id);
    defer query.freeRow(User, std.testing.allocator, &updated);
    try std.testing.expectEqualStrings("alice.new@example.com", updated.email);
    try std.testing.expectEqualStrings("Alice Updated", updated.name);
    try std.testing.expectEqual(@as(i64, 31), updated.age);
    try std.testing.expect(!updated.active);

    // 6. Delete the user
    try query.deleteById(User, &db, row_id);
    const result = query.getById(User, &db, std.testing.allocator, row_id);
    try std.testing.expectError(error.NotFound, result);

    // 7. Count should be 0
    try std.testing.expectEqual(@as(u64, 0), try query.count(User, &db));
}

test "orm integration: multiple records, filter, and pagination" {
    var db = try openTestDb();
    defer db.close();

    // Migrate
    var runner = MigrationRunner.init(&db);
    const migrations = [_]Migration{
        .{ .id = 1, .name = "create_users", .up_sql = User.create_table_sql, .down_sql = User.drop_table_sql },
    };
    try runner.migrate(&migrations);

    // Create 5 users
    const names = [_][]const u8{ "Alice", "Bob", "Charlie", "Diana", "Eve" };
    const emails = [_][]const u8{ "alice@ex.com", "bob@ex.com", "charlie@ex.com", "diana@ex.com", "eve@ex.com" };
    for (names, emails, 0..) |name, email, i| {
        _ = try query.create(User, &db, &.{
            .{ .text = email },
            .{ .text = name },
            .{ .int = @intCast(20 + i) },
            .{ .int = 1 },
        });
    }

    // All should return 5
    var all_rows = try query.all(User, &db, std.testing.allocator);
    defer freeUserRows(&all_rows);
    try std.testing.expectEqual(@as(usize, 5), all_rows.items.len);

    // Count should be 5
    try std.testing.expectEqual(@as(u64, 5), try query.count(User, &db));

    // Filter by name
    var filtered = try query.filter(User, &db, std.testing.allocator, "name = ?", &.{.{ .text = "Bob" }});
    defer freeUserRows(&filtered);
    try std.testing.expectEqual(@as(usize, 1), filtered.items.len);
    try std.testing.expectEqualStrings("Bob", filtered.items[0].name);

    // Filter with limit and offset (page 2 of 2)
    var page = try query.filterLimitOffset(User, &db, std.testing.allocator, "", &.{}, 2, 2);
    defer freeUserRows(&page);
    try std.testing.expectEqual(@as(usize, 2), page.items.len);
    try std.testing.expectEqualStrings("Charlie", page.items[0].name);
    try std.testing.expectEqualStrings("Diana", page.items[1].name);
}

test "orm integration: migration rollback and re-apply" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);
    const migrations = [_]Migration{
        .{ .id = 1, .name = "create_users", .up_sql = User.create_table_sql, .down_sql = User.drop_table_sql },
    };

    // Apply
    try runner.migrate(&migrations);
    try std.testing.expectEqual(@as(u64, 1), try runner.countApplied());

    // Rollback
    try runner.rollback(&migrations, 1);
    try std.testing.expectEqual(@as(u64, 0), try runner.countApplied());

    // Re-apply
    try runner.migrate(&migrations);
    try std.testing.expectEqual(@as(u64, 1), try runner.countApplied());

    // Table should work again after re-apply
    _ = try query.create(User, &db, &.{
        .{ .text = "test@example.com" },
        .{ .text = "Test" },
        .{ .int = 25 },
        .{ .int = 1 },
    });
    try std.testing.expectEqual(@as(u64, 1), try query.count(User, &db));
}
