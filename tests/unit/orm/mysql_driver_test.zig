const std = @import("std");
const build_config = @import("build_config");
const zypher = @import("zypher");
const iface = zypher.orm.driver.interface;
const mysql = zypher.orm.driver.mysql;
const testing = std.testing;

test "mysql driver — MysqlDialect constant" {
    try testing.expectEqualStrings("INT AUTO_INCREMENT PRIMARY KEY", iface.MysqlDialect.pk_type);
    try testing.expectEqualStrings("DOUBLE", iface.MysqlDialect.float_type);
    try testing.expectEqualStrings("TINYINT(1)", iface.MysqlDialect.bool_type);
    try testing.expectEqualStrings("TEXT", iface.MysqlDialect.text_type);
}

test "mysql driver — open/exec/prepare/bind/step/column roundtrip" {
    if (!build_config.has_mysql) return error.SkipZigTest;
    const gpa = testing.allocator;

    const cfg = try getTestConfig(gpa);
    defer if (!std.mem.eql(u8, cfg.user, "root")) gpa.free(cfg.user);

    var my_db = try openDb(gpa, cfg);
    defer my_db.close();

    try my_db.exec("DROP TABLE IF EXISTS zypher_my_test");
    try my_db.exec("CREATE TABLE zypher_my_test (id INT AUTO_INCREMENT PRIMARY KEY, label TEXT NOT NULL, score INT NOT NULL)");

    try my_db.exec("INSERT INTO zypher_my_test (label, score) VALUES ('alpha', 100)");
    try my_db.exec("INSERT INTO zypher_my_test (label, score) VALUES ('beta', 200)");

    var insert_stmt = try my_db.prepare("INSERT INTO zypher_my_test (label, score) VALUES (?, ?)");
    try insert_stmt.bind(.{ .text = "gamma" }, 1);
    try insert_stmt.bind(.{ .int = 300 }, 2);
    _ = try insert_stmt.step();
    insert_stmt.finalize();

    var select_stmt = try my_db.prepare("SELECT id, label, score FROM zypher_my_test WHERE score > ? ORDER BY score");
    try select_stmt.bind(.{ .int = 150 }, 1);

    var row_count: usize = 0;
    while (try select_stmt.step()) {
        row_count += 1;
        const id = try select_stmt.column(.integer, 0);
        const label = try select_stmt.column(.text, 1);
        const score = try select_stmt.column(.integer, 2);
        try testing.expect(id == .int);
        try testing.expect(label == .text);
        try testing.expect(score == .int);
    }
    try testing.expectEqual(@as(usize, 2), row_count);
    select_stmt.finalize();

    try my_db.exec("DROP TABLE IF EXISTS zypher_my_test");
}

test "mysql driver — RelationalDb vtable dispatch" {
    if (!build_config.has_mysql) return error.SkipZigTest;
    const gpa = testing.allocator;

    const cfg = try getTestConfig(gpa);
    defer if (!std.mem.eql(u8, cfg.user, "root")) gpa.free(cfg.user);

    var my_db = try openDb(gpa, cfg);
    defer my_db.close();

    const db: iface.RelationalDb = my_db.asRelationalDb();
    try testing.expectEqualDeep(iface.MysqlDialect, db.dialect());

    try db.exec("DROP TABLE IF EXISTS zypher_vt_test");
    try db.exec("CREATE TABLE zypher_vt_test (id INT AUTO_INCREMENT PRIMARY KEY, val TEXT NOT NULL)");

    var stmt = try db.prepare("INSERT INTO zypher_vt_test (val) VALUES (?)");
    defer stmt.finalize();

    try stmt.bind(.{ .text = "hello-vtable" }, 1);
    _ = try stmt.step();
    try stmt.reset();
    try stmt.bind(.{ .text = "hello-vtable2" }, 1);
    _ = try stmt.step();

    var sel = try db.prepare("SELECT val FROM zypher_vt_test WHERE val = ?");
    defer sel.finalize();
    try sel.bind(.{ .text = "hello-vtable2" }, 1);

    const has_row = try sel.step();
    try testing.expect(has_row);
    const val = try sel.column(.text, 0);
    try testing.expectEqualStrings("hello-vtable2", val.text);

    try db.exec("DROP TABLE IF EXISTS zypher_vt_test");
}

test "mysql driver — error on bad SQL" {
    if (!build_config.has_mysql) return error.SkipZigTest;
    const gpa = testing.allocator;

    const cfg = try getTestConfig(gpa);
    defer if (!std.mem.eql(u8, cfg.user, "root")) gpa.free(cfg.user);

    var my_db = try openDb(gpa, cfg);
    defer my_db.close();

    try testing.expectError(error.ExecFailed, my_db.exec("INVALID SQL HERE"));
    try testing.expectError(error.PrepareFailed, my_db.prepare("BAD SQL"));
}

test "mysql driver — close is idempotent" {
    if (!build_config.has_mysql) return error.SkipZigTest;
    const gpa = testing.allocator;

    const cfg = try getTestConfig(gpa);
    defer if (!std.mem.eql(u8, cfg.user, "root")) gpa.free(cfg.user);

    var my_db = try openDb(gpa, cfg);
    my_db.close();
    my_db.close();
}

fn openDb(gpa: std.mem.Allocator, cfg: TestConfig) !mysql.MysqlDb {
    return mysql.MysqlDb.open(gpa, .{
        .host = cfg.host,
        .user = cfg.user,
        .pass = cfg.pass,
        .db = cfg.db,
        .port = cfg.port,
    }) catch |err| switch (err) {
        error.OpenFailed => return error.SkipZigTest,
        else => |e| return e,
    };
}

const TestConfig = struct {
    host: [:0]const u8 = "127.0.0.1",
    user: [:0]const u8 = "root",
    pass: [:0]const u8 = "",
    db: [:0]const u8 = "zypher_test",
    port: u16 = 3306,
};

fn getTestConfig(gpa: std.mem.Allocator) !TestConfig {
    const env_val = std.c.getenv("ZYPHR_MY_TEST_CONNSTR") orelse return TestConfig{};
    const env = std.mem.sliceTo(env_val, 0);
    // Format: "host=HOST user=USER pass=PASS db=DB port=PORT"
    var cfg = TestConfig{};
    var it = std.mem.splitScalar(u8, env, ' ');
    while (it.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            const key = pair[0..eq];
            const val = pair[eq + 1 ..];
            if (std.mem.eql(u8, key, "host")) {
                cfg.host = try gpa.dupeSentinel(u8, val, 0);
            } else if (std.mem.eql(u8, key, "user")) {
                cfg.user = try gpa.dupeSentinel(u8, val, 0);
            } else if (std.mem.eql(u8, key, "pass")) {
                cfg.pass = try gpa.dupeSentinel(u8, val, 0);
            } else if (std.mem.eql(u8, key, "db")) {
                cfg.db = try gpa.dupeSentinel(u8, val, 0);
            } else if (std.mem.eql(u8, key, "port")) {
                cfg.port = try std.fmt.parseInt(u16, val, 10);
            }
        }
    }
    return cfg;
}
