const std = @import("std");
const build_config = @import("build_config");
const zypher = @import("zypher");
const config = zypher.orm.config;
const Server = zypher.core.Server;

test "SqliteConfig default path is db.sqlite" {
    const cfg = config.SqliteConfig{};
    try std.testing.expectEqualStrings("db.sqlite", cfg.path);
}

test "DatabaseConfig tagged union constructs each variant" {
    const sqlite_cfg = config.DatabaseConfig{ .sqlite = .{ .path = ":memory:" } };
    try std.testing.expect(sqlite_cfg == .sqlite);

    const pg_cfg = config.DatabaseConfig{ .postgres = .{ .connstr = "postgresql://localhost/mydb" } };
    try std.testing.expect(pg_cfg == .postgres);

    const mysql_cfg = config.DatabaseConfig{ .mysql = .{ .db = "mydb" } };
    try std.testing.expect(mysql_cfg == .mysql);

    const mongo_cfg = config.DatabaseConfig{ .mongo = .{ .uri = "mongodb://localhost:27017", .default_db = "mydb" } };
    try std.testing.expect(mongo_cfg == .mongo);

    const redis_cfg = config.DatabaseConfig{ .redis = .{ .host = "127.0.0.1" } };
    try std.testing.expect(redis_cfg == .redis);
}

test "openDatabase with sqlite :memory: succeeds and returns relational" {
    const gpa = std.testing.allocator;
    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    try std.testing.expect(result.open_db.kind == .relational);
    try std.testing.expect(result.relational != null);
    try std.testing.expect(result.document == null);
    try std.testing.expect(result.kv == null);
}

test "openDatabase with disabled postgres returns DriverNotEnabled" {
    if (build_config.has_postgres) return;
    const result = config.openDatabase(std.testing.allocator, .{
        .postgres = .{ .connstr = "postgresql://localhost/test" },
    });
    try std.testing.expectError(error.DriverNotEnabled, result);
}

test "openDatabase with disabled mysql returns DriverNotEnabled" {
    if (build_config.has_mysql) return;
    const result = config.openDatabase(std.testing.allocator, .{
        .mysql = .{ .db = "test" },
    });
    try std.testing.expectError(error.DriverNotEnabled, result);
}

test "openDatabase with disabled mongodb returns DriverNotEnabled" {
    if (build_config.has_mongodb) return;
    const result = config.openDatabase(std.testing.allocator, .{
        .mongo = .{ .uri = "mongodb://localhost:27017", .default_db = "test" },
    });
    try std.testing.expectError(error.DriverNotEnabled, result);
}

test "openDatabase with disabled redis returns DriverNotEnabled" {
    if (build_config.has_redis) return;
    const result = config.openDatabase(std.testing.allocator, .{
        .redis = .{ .host = "127.0.0.1" },
    });
    try std.testing.expectError(error.DriverNotEnabled, result);
}

test "RelationalDb from openDatabase(sqlite) can exec" {
    const gpa = std.testing.allocator;
    var result = try config.openDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer result.open_db.close(gpa);

    const db = result.relational.?;
    try db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)");

    var stmt = try db.prepare("INSERT INTO test (val) VALUES (?)");
    defer stmt.finalize();
    try stmt.bind(.{ .text = "hello" }, 1);
    _ = try stmt.step();
}

test "App.useDatabase with sqlite :memory: and App.db() returns RelationalDb" {
    const gpa = std.testing.allocator;
    var app = zypher.core.App.init(gpa, Server.Config{
        .port = 0,
        .host = "127.0.0.1",
    });

    try app.useDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer app.deinit();

    const db = try app.db();
    try db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY)");
    _ = db.dialect();
}

test "App.db() before useDatabase returns NoDatabaseConfigured" {
    const gpa = std.testing.allocator;
    var app = zypher.core.App.init(gpa, Server.Config{
        .port = 0,
        .host = "127.0.0.1",
    });
    defer app.deinit();

    try std.testing.expectError(error.NoDatabaseConfigured, app.db());
}

test "App.documentStore() on relational db returns WrongStoreType" {
    const gpa = std.testing.allocator;
    var app = zypher.core.App.init(gpa, Server.Config{
        .port = 0,
        .host = "127.0.0.1",
    });

    try app.useDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    defer app.deinit();

    try std.testing.expectError(error.WrongStoreType, app.documentStore());
    try std.testing.expectError(error.WrongStoreType, app.kvStore());
}

test "App.deinit closes database without leaks" {
    const gpa = std.testing.allocator;
    var app = zypher.core.App.init(gpa, Server.Config{
        .port = 0,
        .host = "127.0.0.1",
    });

    try app.useDatabase(gpa, .{ .sqlite = .{ .path = ":memory:" } });
    app.deinit();
}
