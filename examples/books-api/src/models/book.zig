const std = @import("std");
const zypher = @import("zypher");

const schema = zypher.orm.schema;
const query = zypher.orm.query;
const sqlite = zypher.orm.sqlite;

pub const BookFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    title: schema.FieldDef = schema.Field("title", .text, .{ .required = true }),
    author: schema.FieldDef = schema.Field("author", .text, .{ .required = true }),
    year: schema.FieldDef = schema.Field("year", .integer, .{}),
    created_at: schema.FieldDef = schema.Field("created_at", .integer, .{ .required = true }),
};

pub const Book = schema.Model("books", BookFields);
pub const BookRow = query.RowType(Book);
pub const BookList = std.ArrayList(BookRow);

pub const BookInput = struct {
    title: []const u8,
    author: []const u8,
    year: i64,
};

pub fn migrate(db: *sqlite.Db) !void {
    try db.exec(Book.create_table_sql);
}

pub fn create(db: *sqlite.Db, input: BookInput, now: i64) !i64 {
    return query.create(Book, db, &.{
        .{ .text = input.title },
        .{ .text = input.author },
        .{ .int = input.year },
        .{ .int = now },
    });
}

pub fn list(db: *sqlite.Db, allocator: std.mem.Allocator) !BookList {
    return query.all(Book, db, allocator);
}

pub fn get(db: *sqlite.Db, allocator: std.mem.Allocator, id: i64) !BookRow {
    return query.getById(Book, db, allocator, id);
}

pub fn update(db: *sqlite.Db, id: i64, input: BookInput, created_at: i64) !void {
    try query.updateById(Book, db, id, &.{
        .{ .text = input.title },
        .{ .text = input.author },
        .{ .int = input.year },
        .{ .int = created_at },
    });
}

pub fn delete(db: *sqlite.Db, id: i64) !void {
    try query.deleteById(Book, db, id);
}

pub fn freeRows(allocator: std.mem.Allocator, rows: *BookList) void {
    for (rows.items) |*row| query.freeRow(Book, allocator, row);
    rows.deinit(allocator);
}

pub fn freeRow(allocator: std.mem.Allocator, row: *BookRow) void {
    query.freeRow(Book, allocator, row);
}
