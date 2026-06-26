const std = @import("std");
const schema = @import("zypher").orm.schema;
const iface = @import("zypher").orm.driver.interface;

const FieldKind = schema.FieldKind;
const DefaultValue = schema.DefaultValue;
const FieldDef = schema.FieldDef;
const Field = schema.Field;
const Model = schema.Model;
const SqliteDialect = iface.SqliteDialect;
const PostgresDialect = iface.PostgresDialect;
const MysqlDialect = iface.MysqlDialect;

const UserFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    name: FieldDef = Field("name", .text, .{ .required = true }),
    age: FieldDef = Field("age", .integer, .{}),
    email: FieldDef = Field("email", .text, .{ .unique = true }),
};
const User = Model("users", UserFields);

const PostFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    title: FieldDef = Field("title", .text, .{ .required = true }),
    body: FieldDef = Field("body", .text, .{}),
    author_id: FieldDef = Field("author_id", .integer, .{ .foreign = "users.id" }),
    published: FieldDef = Field("published", .boolean, .{ .default = DefaultValue{ .boolean = false } }),
};
const Post = Model("posts", PostFields);

const MetricFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    value: FieldDef = Field("value", .float, .{}),
    label: FieldDef = Field("label", .text, .{}),
};
const Metric = Model("metrics", MetricFields);

test "dialect: createTableSql(SqliteDialect) matches backward compat create_table_sql" {
    try std.testing.expectEqualStrings(User.create_table_sql, User.createTableSql(SqliteDialect));
}

test "dialect: createTableSql(PostgresDialect) uses BIGSERIAL PRIMARY KEY and DOUBLE PRECISION" {
    const sql = User.createTableSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "BIGSERIAL PRIMARY KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DOUBLE PRECISION") == null); // no float fields in User
}

test "dialect: createTableSql(PostgresDialect) uses DOUBLE PRECISION for float fields" {
    const sql = Metric.createTableSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "value DOUBLE PRECISION") != null);
}

test "dialect: createTableSql(MysqlDialect) uses INT AUTO_INCREMENT PRIMARY KEY and DOUBLE for float" {
    const sql = Metric.createTableSql(MysqlDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INT AUTO_INCREMENT PRIMARY KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "value DOUBLE") != null);
}

test "dialect: createTableSql(PostgresDialect) uses BOOLEAN for bool fields" {
    const sql = Post.createTableSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "published BOOLEAN") != null);
}

test "dialect: createTableSql(MysqlDialect) uses TINYINT(1) for bool fields" {
    const sql = Post.createTableSql(MysqlDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "published TINYINT(1)") != null);
}

test "dialect: insertSql(PostgresDialect) produces $1, $2 placeholders" {
    const sql = User.insertSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$2") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$3") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "?") == null);
}

test "dialect: insertSql(MysqlDialect) produces ? placeholder" {
    const sql = User.insertSql(MysqlDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "?") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$1") == null);
}

test "dialect: selectByIdSql(PostgresDialect) uses $1" {
    const sql = User.selectByIdSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id = $1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "?") == null);
}

test "dialect: selectByIdSql(SqliteDialect) matches backward compat" {
    try std.testing.expectEqualStrings(User.select_by_id_sql, User.selectByIdSql(SqliteDialect));
}

test "dialect: updateByIdSql(PostgresDialect) uses $N placeholders" {
    const sql = User.updateByIdSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$2") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "$3") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id = $4") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "?") == null);
}

test "dialect: migrationHistoryTableSql(SqliteDialect) uses strftime" {
    const sql = schema.migrationHistoryTableSql(SqliteDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "zypher_migrations") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "strftime('%s','now')") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INTEGER") != null);
}

test "dialect: migrationHistoryTableSql(PostgresDialect) uses BIGINT and EXTRACT" {
    const sql = schema.migrationHistoryTableSql(PostgresDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "zypher_migrations") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "BIGINT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "EXTRACT(EPOCH FROM NOW())::BIGINT") != null);
}

test "dialect: migrationHistoryTableSql(MysqlDialect) uses BIGINT and UNIX_TIMESTAMP" {
    const sql = schema.migrationHistoryTableSql(MysqlDialect);
    try std.testing.expect(std.mem.indexOf(u8, sql, "zypher_migrations") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "BIGINT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "UNIX_TIMESTAMP()") != null);
}
