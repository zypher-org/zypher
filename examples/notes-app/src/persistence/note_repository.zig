const std = @import("std");
const zypher = @import("zypher");
const domain = @import("../domain/note.zig");

const sqlite = zypher.orm.sqlite;
const query = zypher.orm.query;

pub const NoteList = std.ArrayList(domain.NoteRow);

pub fn migrate(db: *sqlite.Db) !void {
    try db.exec(domain.Note.create_table_sql);
}

pub fn create(db: *sqlite.Db, input: domain.NoteInput, now: i64) !i64 {
    return query.create(domain.Note, db, &.{
        .{ .text = input.title },
        .{ .text = input.body },
        .{ .text = input.tags },
        .{ .int = if (input.pinned) 1 else 0 },
        .{ .int = if (input.archived) 1 else 0 },
        .{ .int = now },
        .{ .int = now },
    });
}

pub fn listActive(db: *sqlite.Db, allocator: std.mem.Allocator) !NoteList {
    return query.filterOrderLimitOffset(
        domain.Note,
        db,
        allocator,
        "archived = ?",
        &.{.{ .int = 0 }},
        "pinned DESC, updated_at DESC, id DESC",
        100,
        0,
    );
}

pub fn listArchived(db: *sqlite.Db, allocator: std.mem.Allocator) !NoteList {
    return query.filterOrderLimitOffset(
        domain.Note,
        db,
        allocator,
        "archived = ?",
        &.{.{ .int = 1 }},
        "updated_at DESC, id DESC",
        100,
        0,
    );
}

pub fn search(db: *sqlite.Db, allocator: std.mem.Allocator, term: []const u8) !NoteList {
    const pattern = try std.fmt.allocPrint(allocator, "%{s}%", .{term});
    defer allocator.free(pattern);
    return query.filterOrderLimitOffset(
        domain.Note,
        db,
        allocator,
        "archived = ? AND (title LIKE ? OR body LIKE ? OR tags LIKE ?)",
        &.{ .{ .int = 0 }, .{ .text = pattern }, .{ .text = pattern }, .{ .text = pattern } },
        "pinned DESC, updated_at DESC, id DESC",
        100,
        0,
    );
}

pub fn get(db: *sqlite.Db, allocator: std.mem.Allocator, id: i64) !domain.NoteRow {
    return query.getById(domain.Note, db, allocator, id);
}

pub fn update(db: *sqlite.Db, id: i64, input: domain.NoteInput, now: i64) !void {
    try query.updateById(domain.Note, db, id, &.{
        .{ .text = input.title },
        .{ .text = input.body },
        .{ .text = input.tags },
        .{ .int = if (input.pinned) 1 else 0 },
        .{ .int = if (input.archived) 1 else 0 },
        .{ .int = now },
        .{ .int = now },
    });
}

pub fn archive(db: *sqlite.Db, allocator: std.mem.Allocator, id: i64, archived: bool, now: i64) !void {
    var row = try query.getById(domain.Note, db, allocator, id);
    defer query.freeRow(domain.Note, allocator, &row);
    try query.updateById(domain.Note, db, id, &.{
        .{ .text = row[1] },
        .{ .text = row[2] },
        .{ .text = row[3] },
        .{ .int = if (row[4]) 1 else 0 },
        .{ .int = if (archived) 1 else 0 },
        .{ .int = row[6] },
        .{ .int = now },
    });
}

pub fn delete(db: *sqlite.Db, id: i64) !void {
    try query.deleteById(domain.Note, db, id);
}

pub fn freeRows(allocator: std.mem.Allocator, rows: *NoteList) void {
    for (rows.items) |*row| {
        query.freeRow(domain.Note, allocator, row);
    }
    rows.deinit(allocator);
}

pub fn freeRow(allocator: std.mem.Allocator, row: *domain.NoteRow) void {
    query.freeRow(domain.Note, allocator, row);
}
