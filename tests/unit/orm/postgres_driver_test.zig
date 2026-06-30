const std = @import("std");
const build_config = @import("build_config");
const zypher = @import("zypher");
const iface = zypher.orm.driver.interface;
const postgres = zypher.orm.driver.postgres;
const testing = std.testing;

test "postgres driver — translatePlaceholders replaces ? with $N" {
    const gpa = testing.allocator;
    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "SELECT 1", .expected = "SELECT 1" },
        .{ .input = "SELECT ?", .expected = "SELECT $1" },
        .{ .input = "SELECT ?, ?", .expected = "SELECT $1, $2" },
        .{ .input = "INSERT INTO t VALUES (?, ?, ?)", .expected = "INSERT INTO t VALUES ($1, $2, $3)" },
        .{ .input = "? = ? AND ? IS NULL", .expected = "$1 = $2 AND $3 IS NULL" },
        .{ .input = "", .expected = "" },
        .{ .input = "?", .expected = "$1" },
        .{ .input = "??", .expected = "$1$2" },
    };
    for (cases) |c| {
        const got = try postgres.translatePlaceholders(c.input, gpa);
        defer gpa.free(got);
        try testing.expectEqualStrings(c.expected, got);
    }
}

test "postgres driver — translatePlaceholders handles null allocator" {
    const got = postgres.translatePlaceholders("SELECT ?", testing.failing_allocator);
    try testing.expectError(error.AllocatorFailed, got);
}

test "postgres driver — PostgresDialect constant" {
    try testing.expectEqualStrings("BIGSERIAL PRIMARY KEY", iface.PostgresDialect.pk_type);
    try testing.expectEqualStrings("DOUBLE PRECISION", iface.PostgresDialect.float_type);
    try testing.expectEqualStrings("BOOLEAN", iface.PostgresDialect.bool_type);
    try testing.expectEqualStrings("TEXT", iface.PostgresDialect.text_type);
}

test "postgres driver — open/exec/prepare/bind/step/column/finalize roundtrip" {
    if (!build_config.has_postgres) return error.SkipZigTest;
    const gpa = testing.allocator;

    const connstr = try getTestConnstr(gpa);
    defer gpa.free(connstr);

    var pg_db = try postgres.PostgresDb.open(gpa, connstr);
    defer pg_db.close();

    try pg_db.exec("DROP TABLE IF EXISTS zypher_pg_test");
    try pg_db.exec("CREATE TABLE zypher_pg_test (id BIGSERIAL PRIMARY KEY, label TEXT NOT NULL, score INTEGER NOT NULL)");

    try pg_db.exec("INSERT INTO zypher_pg_test (label, score) VALUES ('alpha', 100)");
    try pg_db.exec("INSERT INTO zypher_pg_test (label, score) VALUES ('beta', 200)");
    try testing.expect(pg_db.changes() >= 1);

    var insert_stmt = try pg_db.prepare("INSERT INTO zypher_pg_test (label, score) VALUES (?, ?)");
    try insert_stmt.bind(.{ .text = "gamma" }, 1);
    try insert_stmt.bind(.{ .int = 300 }, 2);
    _ = try insert_stmt.step();
    insert_stmt.finalize();

    var select_stmt = try pg_db.prepare("SELECT id, label, score FROM zypher_pg_test WHERE score > ? ORDER BY score");
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

    try pg_db.exec("DROP TABLE IF EXISTS zypher_pg_test");
}

test "postgres driver — RelationalDb vtable dispatch" {
    if (!build_config.has_postgres) return error.SkipZigTest;
    const gpa = testing.allocator;

    const connstr = try getTestConnstr(gpa);
    defer gpa.free(connstr);

    var pg_db = try postgres.PostgresDb.open(gpa, connstr);
    defer pg_db.close();

    const db: iface.RelationalDb = pg_db.asRelationalDb();
    try testing.expectEqualDeep(iface.PostgresDialect, db.dialect());

    try db.exec("DROP TABLE IF EXISTS zypher_vt_test");
    try db.exec("CREATE TABLE zypher_vt_test (id BIGSERIAL PRIMARY KEY, val TEXT NOT NULL)");

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

test "postgres driver — error on bad SQL" {
    if (!build_config.has_postgres) return error.SkipZigTest;
    const gpa = testing.allocator;

    const connstr = try getTestConnstr(gpa);
    defer gpa.free(connstr);

    var pg_db = try postgres.PostgresDb.open(gpa, connstr);
    defer pg_db.close();

    try testing.expectError(error.ExecFailed, pg_db.exec("INVALID SQL HERE"));
    try testing.expectError(error.PrepareFailed, pg_db.prepare("BAD SQL"));
}

test "postgres driver — close is idempotent" {
    if (!build_config.has_postgres) return error.SkipZigTest;
    const gpa = testing.allocator;

    const connstr = try getTestConnstr(gpa);
    defer gpa.free(connstr);

    var pg_db = try postgres.PostgresDb.open(gpa, connstr);
    pg_db.close();
    pg_db.close();
}

fn getTestConnstr(gpa: std.mem.Allocator) ![:0]const u8 {
    const connstr = "host=localhost dbname=zypher_test user=zypher password=zypher";
    const buf = try gpa.alloc(u8, connstr.len + 1);
    @memcpy(buf[0..connstr.len], connstr);
    buf[connstr.len] = 0;
    return buf[0..connstr.len :0];
}
