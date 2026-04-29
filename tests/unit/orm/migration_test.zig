const std = @import("std");
const sqlite = @import("zypher").orm.sqlite;
const migration = @import("zypher").orm.migration;

const Db = sqlite.Db;
const Migration = migration.Migration;
const MigrationRunner = migration.MigrationRunner;
const MigrationStatus = migration.MigrationStatus;

// ── Helpers ───────────────────────────────────────────────────────────────

fn openTestDb() !Db {
    return Db.open(std.testing.allocator, ":memory:");
}

// ── Test migrations ───────────────────────────────────────────────────────

const migrations = [_]Migration{
    .{ .id = 1, .name = "create_users", .up_sql = "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)", .down_sql = "DROP TABLE IF EXISTS users" },
    .{ .id = 2, .name = "create_posts", .up_sql = "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL, author_id INTEGER REFERENCES users(id))", .down_sql = "DROP TABLE IF EXISTS posts" },
    .{ .id = 3, .name = "add_email_to_users", .up_sql = "ALTER TABLE users ADD COLUMN email TEXT", .down_sql = "SELECT 1" },
};

// ── Tests ─────────────────────────────────────────────────────────────────

test "migration: runner creates history table on first run" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);
    try runner.migrate(&migrations);

    // History table should exist
    var stmt = try db.prepare("SELECT COUNT(*) FROM zypher_migrations");
    defer stmt.finalize();
    const has_row = try stmt.step();
    try std.testing.expect(has_row);
}

test "migration: applies all pending migrations" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);
    try runner.migrate(&migrations);

    // All 3 tables/columns should exist
    try db.exec("INSERT INTO users (name) VALUES ('alice')");
    try db.exec("INSERT INTO posts (title, author_id) VALUES ('hello', 1)");
    try db.exec("UPDATE users SET email = 'alice@example.com' WHERE id = 1");
}

test "migration: is idempotent (running twice is safe)" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);
    try runner.migrate(&migrations);
    // Run again — should skip already-applied migrations
    try runner.migrate(&migrations);

    // Count applied migrations
    try std.testing.expectEqual(@as(u64, 3), try runner.countApplied());
}

test "migration: status lists applied and pending" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);

    // Before any migration, all should be pending
    const statuses_before = try runner.status(std.testing.allocator, &migrations);
    defer std.testing.allocator.free(statuses_before);
    try std.testing.expectEqual(@as(usize, 3), statuses_before.len);
    for (statuses_before) |s| {
        try std.testing.expect(!s.applied);
    }

    // Apply first migration only
    const first_only = [_]Migration{migrations[0]};
    try runner.migrate(&first_only);

    const statuses_after = try runner.status(std.testing.allocator, &migrations);
    defer std.testing.allocator.free(statuses_after);
    try std.testing.expect(statuses_after[0].applied);
    try std.testing.expect(!statuses_after[1].applied);
    try std.testing.expect(!statuses_after[2].applied);
}

test "migration: rollback reverts a migration" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);
    try runner.migrate(&migrations);

    // Rollback the last migration (add_email_to_users)
    try runner.rollback(&migrations, 1);

    // Posts table should still exist (only last migration rolled back)
    try db.exec("INSERT INTO posts (title, author_id) VALUES ('test', 1)");

    // Count should be 2 now
    try std.testing.expectEqual(@as(u64, 2), try runner.countApplied());
}

test "migration: rollback multiple migrations" {
    var db = try openTestDb();
    defer db.close();

    var runner = MigrationRunner.init(&db);
    try runner.migrate(&migrations);

    // Rollback 2 migrations
    try runner.rollback(&migrations, 2);

    // Only first migration should remain
    try std.testing.expectEqual(@as(u64, 1), try runner.countApplied());
}
