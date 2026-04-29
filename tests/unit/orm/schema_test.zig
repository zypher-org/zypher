const std = @import("std");
const schema = @import("zypher").orm.schema;

const FieldKind = schema.FieldKind;
const DefaultValue = schema.DefaultValue;
const FieldDef = schema.FieldDef;
const Field = schema.Field;
const Model = schema.Model;

// ── Test model definitions ────────────────────────────────────────────────

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

// ── Tests ─────────────────────────────────────────────────────────────────

test "schema: Model has correct table name" {
    try std.testing.expectEqualStrings("users", User.table_name);
    try std.testing.expectEqualStrings("posts", Post.table_name);
    try std.testing.expectEqualStrings("metrics", Metric.table_name);
}

test "schema: Model has correct field count" {
    try std.testing.expectEqual(@as(usize, 4), User.fields_len);
    try std.testing.expectEqual(@as(usize, 5), Post.fields_len);
    try std.testing.expectEqual(@as(usize, 3), Metric.fields_len);
}

test "schema: primary key field is detected" {
    try std.testing.expect(User.fieldAt(0).primary);
    try std.testing.expect(!User.fieldAt(1).primary);
    try std.testing.expect(Post.fieldAt(0).primary);
}

test "schema: field kinds are correct" {
    try std.testing.expectEqual(FieldKind.integer, User.fieldAt(0).kind);
    try std.testing.expectEqual(FieldKind.text, User.fieldAt(1).kind);
    try std.testing.expectEqual(FieldKind.integer, User.fieldAt(2).kind);
    try std.testing.expectEqual(FieldKind.text, User.fieldAt(3).kind);
}

test "schema: field names are correct" {
    try std.testing.expectEqualStrings("id", User.fieldAt(0).name);
    try std.testing.expectEqualStrings("name", User.fieldAt(1).name);
    try std.testing.expectEqualStrings("age", User.fieldAt(2).name);
    try std.testing.expectEqualStrings("email", User.fieldAt(3).name);
}

test "schema: required constraint" {
    try std.testing.expect(!User.fieldAt(0).required); // id — auto-generated
    try std.testing.expect(User.fieldAt(1).required); // name
    try std.testing.expect(!User.fieldAt(2).required); // age
}

test "schema: unique constraint" {
    try std.testing.expect(!User.fieldAt(0).unique);
    try std.testing.expect(!User.fieldAt(1).unique);
    try std.testing.expect(User.fieldAt(3).unique); // email
}

test "schema: foreign key constraint" {
    try std.testing.expect(Post.fieldAt(3).foreign != null);
    try std.testing.expectEqualStrings("users.id", Post.fieldAt(3).foreign.?);
    try std.testing.expect(User.fieldAt(0).foreign == null);
}

test "schema: default value" {
    try std.testing.expect(Post.fieldAt(4).default != null);
    try std.testing.expectEqual(false, Post.fieldAt(4).default.?.boolean);
    try std.testing.expect(User.fieldAt(0).default == null);
}

test "schema: createTable SQL generation" {
    const sql = User.create_table_sql;
    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE IF NOT EXISTS users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "id INTEGER PRIMARY KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name TEXT NOT NULL") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "age INTEGER") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "email TEXT UNIQUE") != null);
}

test "schema: createTable SQL with foreign key" {
    const sql = Post.create_table_sql;
    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE IF NOT EXISTS posts") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "author_id INTEGER REFERENCES users.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "published BOOLEAN DEFAULT 0") != null);
}

test "schema: dropTable SQL generation" {
    try std.testing.expectEqualStrings("DROP TABLE IF EXISTS users", User.drop_table_sql);
}

test "schema: insert SQL generation" {
    const sql = User.insert_sql;
    try std.testing.expect(std.mem.indexOf(u8, sql, "INSERT INTO users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "?") != null);
}

test "schema: selectAll SQL generation" {
    try std.testing.expectEqualStrings("SELECT id, name, age, email FROM users", User.select_all_sql);
}

test "schema: selectById SQL generation" {
    try std.testing.expect(std.mem.indexOf(u8, User.select_by_id_sql, "SELECT id, name, age, email FROM users WHERE id = ?") != null);
}

test "schema: updateById SQL generation" {
    const sql = User.update_by_id_sql;
    try std.testing.expect(std.mem.indexOf(u8, sql, "UPDATE users SET") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE id = ?") != null);
}

test "schema: deleteById SQL generation" {
    try std.testing.expectEqualStrings("DELETE FROM users WHERE id = ?", User.delete_by_id_sql);
}

test "schema: field count excludes auto-generated primary key in insert" {
    // Insert should not include the auto-increment primary key
    try std.testing.expectEqual(@as(comptime_int, 3), User.insert_field_count);
}
