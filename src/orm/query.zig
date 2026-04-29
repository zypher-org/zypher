/// zypher ORM — runtime query execution using comptime schema SQL.
const std = @import("std");
const sqlite = @import("sqlite.zig");
const schema = @import("schema.zig");

const log = std.log.scoped(.query);

pub const QueryError = error{
    NotFound,
    NoRows,
    BindFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    ColumnFailed,
    AllocatorFailed,
};

/// Row type returned by query functions. Fields match the model's FieldDef order.
pub fn RowType(comptime M: type) type {
    comptime {
        var names: [M.fields_len][]const u8 = undefined;
        var types: [M.fields_len]type = undefined;
        var attrs: [M.fields_len]std.builtin.Type.StructField.Attributes = undefined;
        for (0..M.fields_len) |i| {
            const f = M.fieldAt(i);
            names[i] = f.name;
            types[i] = switch (f.kind) {
                .integer => i64,
                .float => f64,
                .text => []const u8,
                .boolean => bool,
            };
            attrs[i] = .{
                .@"align" = null,
                .@"comptime" = false,
                .default_value_ptr = null,
            };
        }
        return @Struct(.auto, null, &names, &types, &attrs);
    }
}

/// Read a row from the current statement step, copying text fields into owned memory.
fn readRow(comptime M: type, stmt: *sqlite.Stmt, gpa: std.mem.Allocator) QueryError!RowType(M) {
    var row: RowType(M) = undefined;
    const row_fields = @typeInfo(RowType(M)).@"struct".fields;
    inline for (0..M.fields_len) |i| {
        const fname = row_fields[i].name;
        const FieldType = row_fields[i].type;
        if (FieldType == i64) {
            const val = stmt.column(.integer, @intCast(i)) catch return error.ColumnFailed;
            @field(row, fname) = val.int;
        } else if (FieldType == f64) {
            const val = stmt.column(.float, @intCast(i)) catch return error.ColumnFailed;
            @field(row, fname) = val.float;
        } else if (FieldType == []const u8) {
            const val = stmt.column(.text, @intCast(i)) catch return error.ColumnFailed;
            const owned = gpa.dupe(u8, val.text) catch return error.AllocatorFailed;
            @field(row, fname) = owned;
        } else if (FieldType == bool) {
            const val = stmt.column(.integer, @intCast(i)) catch return error.ColumnFailed;
            @field(row, fname) = (val.int != 0);
        }
    }
    return row;
}

/// Free owned text memory in a row.
pub fn freeRow(comptime M: type, gpa: std.mem.Allocator, row: *RowType(M)) void {
    const row_fields = @typeInfo(RowType(M)).@"struct".fields;
    inline for (0..M.fields_len) |i| {
        const fname = row_fields[i].name;
        const FieldType = row_fields[i].type;
        if (FieldType == []const u8) {
            const slice = @field(row, fname);
            gpa.free(@constCast(slice));
        }
    }
}

/// INSERT a new record. Returns the rowid.
pub fn create(comptime M: type, db: *sqlite.Db, values: []const sqlite.Value) QueryError!i64 {
    var stmt = db.prepare(M.insert_sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    for (values, 0..) |v, i| {
        stmt.bind(v, @intCast(i + 1)) catch return error.BindFailed;
    }
    _ = stmt.step() catch return error.StepFailed;
    const row_id = db.lastInsertRowId();
    log.info("created record in {s}: rowid={d}", .{ M.table_name, row_id });
    return row_id;
}

/// SELECT by primary key. Returns the row or error.NotFound.
/// Caller owns the row's text memory — call freeRow when done.
pub fn getById(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, id: i64) QueryError!RowType(M) {
    var stmt = db.prepare(M.select_by_id_sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    stmt.bind(.{ .int = id }, 1) catch return error.BindFailed;
    const has_row = stmt.step() catch return error.StepFailed;
    if (!has_row) return error.NotFound;
    return readRow(M, &stmt, gpa);
}

/// SELECT all rows.
/// Caller owns the rows and their text memory — call freeRow on each when done.
pub fn all(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator) QueryError!std.ArrayList(RowType(M)) {
    var list = std.ArrayList(RowType(M)).empty;
    var stmt = db.prepare(M.select_all_sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    while (stmt.step() catch return error.StepFailed) {
        const row = try readRow(M, &stmt, gpa);
        list.append(gpa, row) catch return error.AllocatorFailed;
    }
    log.info("fetched {d} rows from {s}", .{ list.items.len, M.table_name });
    return list;
}

/// UPDATE by primary key.
pub fn updateById(comptime M: type, db: *sqlite.Db, id: i64, values: []const sqlite.Value) QueryError!void {
    var stmt = db.prepare(M.update_by_id_sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    for (values, 0..) |v, i| {
        stmt.bind(v, @intCast(i + 1)) catch return error.BindFailed;
    }
    stmt.bind(.{ .int = id }, @intCast(values.len + 1)) catch return error.BindFailed;
    _ = stmt.step() catch return error.StepFailed;
    log.info("updated record in {s}: id={d}", .{ M.table_name, id });
}

/// DELETE by primary key.
pub fn deleteById(comptime M: type, db: *sqlite.Db, id: i64) QueryError!void {
    var stmt = db.prepare(M.delete_by_id_sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    stmt.bind(.{ .int = id }, 1) catch return error.BindFailed;
    _ = stmt.step() catch return error.StepFailed;
    log.info("deleted record from {s}: id={d}", .{ M.table_name, id });
}

/// COUNT all rows.
pub fn count(comptime M: type, db: *sqlite.Db) QueryError!u64 {
    const sql = "SELECT COUNT(*) FROM " ++ M.table_name;
    var stmt = db.prepare(sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    const has_row = stmt.step() catch return error.StepFailed;
    if (!has_row) return 0;
    const val = stmt.column(.integer, 0) catch return error.ColumnFailed;
    return @intCast(val.int);
}

/// FILTER with WHERE clause. Values are bound as parameters (SQL injection safe).
/// Caller owns the rows and their text memory — call freeRow on each when done.
pub fn filter(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, where: [:0]const u8, values: []const sqlite.Value) QueryError!std.ArrayList(RowType(M)) {
    var list = std.ArrayList(RowType(M)).empty;
    const sql: [:0]const u8 = if (where.len > 0) std.fmt.allocPrintSentinel(gpa, "{s} WHERE {s}", .{ M.select_all_sql, where }, 0) catch return error.AllocatorFailed else M.select_all_sql;
    defer if (where.len > 0) gpa.free(@constCast(sql));
    var stmt = db.prepare(sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    for (values, 0..) |v, i| {
        stmt.bind(v, @intCast(i + 1)) catch return error.BindFailed;
    }
    while (stmt.step() catch return error.StepFailed) {
        const row = try readRow(M, &stmt, gpa);
        list.append(gpa, row) catch return error.AllocatorFailed;
    }
    log.info("filtered {d} rows from {s}", .{ list.items.len, M.table_name });
    return list;
}

/// FILTER with WHERE, LIMIT, and OFFSET.
/// Caller owns the rows and their text memory — call freeRow on each when done.
pub fn filterLimitOffset(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, where: [:0]const u8, values: []const sqlite.Value, limit: u64, offset: u64) QueryError!std.ArrayList(RowType(M)) {
    var list = std.ArrayList(RowType(M)).empty;
    const sql: [:0]const u8 = if (where.len > 0)
        std.fmt.allocPrintSentinel(gpa, "{s} WHERE {s} LIMIT ? OFFSET ?", .{ M.select_all_sql, where }, 0) catch return error.AllocatorFailed
    else
        std.fmt.allocPrintSentinel(gpa, "{s} LIMIT ? OFFSET ?", .{M.select_all_sql}, 0) catch return error.AllocatorFailed;
    defer gpa.free(@constCast(sql));
    var stmt = db.prepare(sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    for (values, 0..) |v, i| {
        stmt.bind(v, @intCast(i + 1)) catch return error.BindFailed;
    }
    const limit_idx: c_int = @intCast(values.len + 1);
    const offset_idx: c_int = @intCast(values.len + 2);
    stmt.bind(.{ .int = @intCast(limit) }, limit_idx) catch return error.BindFailed;
    stmt.bind(.{ .int = @intCast(offset) }, offset_idx) catch return error.BindFailed;
    while (stmt.step() catch return error.StepFailed) {
        const row = try readRow(M, &stmt, gpa);
        list.append(gpa, row) catch return error.AllocatorFailed;
    }
    log.info("filtered {d} rows from {s} (limit={d}, offset={d})", .{ list.items.len, M.table_name, limit, offset });
    return list;
}

test {
    std.testing.refAllDecls(@This());
}
