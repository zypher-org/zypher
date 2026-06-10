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
        @setEvalBranchQuota(2000);
        var types: [M.fields_len]type = undefined;
        for (0..M.fields_len) |i| {
            const f = M.fieldAt(i);
            types[i] = switch (f.kind) {
                .integer => i64,
                .float => f64,
                .text => []const u8,
                .boolean => bool,
            };
        }
        return @Tuple(&types);
    }
}

/// Read a row from the current statement step, copying text fields into owned memory.
fn readRow(comptime M: type, stmt: *sqlite.Stmt, gpa: std.mem.Allocator) QueryError!RowType(M) {
    var row: RowType(M) = undefined;
    inline for (0..M.fields_len) |i| {
        const FieldType = @typeInfo(RowType(M)).@"struct".field_types[i];
        if (FieldType == i64) {
            const val = stmt.column(.integer, @intCast(i)) catch return error.ColumnFailed;
            row[i] = val.int;
        } else if (FieldType == f64) {
            const val = stmt.column(.float, @intCast(i)) catch return error.ColumnFailed;
            row[i] = val.float;
        } else if (FieldType == []const u8) {
            const val = stmt.column(.text, @intCast(i)) catch return error.ColumnFailed;
            const owned = gpa.dupe(u8, val.text) catch return error.AllocatorFailed;
            row[i] = owned;
        } else if (FieldType == bool) {
            const val = stmt.column(.integer, @intCast(i)) catch return error.ColumnFailed;
            row[i] = (val.int != 0);
        }
    }
    return row;
}

/// Free owned text memory in a row.
pub fn freeRow(comptime M: type, gpa: std.mem.Allocator, row: *RowType(M)) void {
    inline for (0..M.fields_len) |i| {
        const FieldType = @typeInfo(RowType(M)).@"struct".field_types[i];
        if (FieldType == []const u8) {
            gpa.free(@constCast(row[i]));
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

/// ORDER BY a column expression. Returns all rows sorted.
/// Caller owns the rows and their text memory — call freeRow on each when done.
pub fn order(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, order_by: []const u8) QueryError!std.ArrayList(RowType(M)) {
    var list = std.ArrayList(RowType(M)).empty;
    const sql: [:0]const u8 = if (order_by.len > 0)
        std.fmt.allocPrintSentinel(gpa, "{s} ORDER BY {s}", .{ M.select_all_sql, order_by }, 0) catch return error.AllocatorFailed
    else
        M.select_all_sql;
    defer if (order_by.len > 0) gpa.free(@constCast(sql));
    var stmt = db.prepare(sql) catch return error.PrepareFailed;
    defer stmt.finalize();
    while (stmt.step() catch return error.StepFailed) {
        const row = try readRow(M, &stmt, gpa);
        list.append(gpa, row) catch return error.AllocatorFailed;
    }
    log.info("ordered rows from {s} by '{s}'", .{ M.table_name, order_by });
    return list;
}

/// Chainable QuerySet builder. Each method returns `*Self` for chaining.
/// Call `.exec()` to execute the built query.
pub fn QuerySet(comptime M: type) type {
    return struct {
        const Self = @This();
        db: *sqlite.Db,
        gpa: std.mem.Allocator,
        where_clause: [:0]const u8 = "",
        where_vals: std.ArrayList(sqlite.Value),
        order_clause: []const u8 = "",
        limit_val: ?u64 = null,
        offset_val: ?u64 = null,

        pub fn init(db: *sqlite.Db, gpa: std.mem.Allocator) Self {
            return .{ .db = db, .gpa = gpa, .where_vals = std.ArrayList(sqlite.Value).empty };
        }

        pub fn deinit(self: *Self) void {
            self.where_vals.deinit(self.gpa);
        }

        pub fn filterBy(self: *Self, where: [:0]const u8, values: []const sqlite.Value) *Self {
            self.where_clause = where;
            for (values) |v| self.where_vals.append(self.gpa, v) catch return self;
            return self;
        }

        pub fn orderBy(self: *Self, order_by: []const u8) *Self {
            self.order_clause = order_by;
            return self;
        }

        pub fn limit(self: *Self, n: u64) *Self {
            self.limit_val = n;
            return self;
        }

        pub fn offset(self: *Self, n: u64) *Self {
            self.offset_val = n;
            return self;
        }

        /// Execute the query and return results.
        pub fn exec(self: *Self) QueryError!std.ArrayList(RowType(M)) {
            const hw = self.where_clause.len > 0;
            const ho = self.order_clause.len > 0;
            const hl = self.limit_val != null;
            const hof = self.offset_val != null;

            if (hw and ho and hl and hof) {
                return filterOrderLimitOffset(M, self.db, self.gpa, self.where_clause, self.where_vals.items, self.order_clause, self.limit_val.?, self.offset_val.?);
            }
            if (hw and hl and hof) {
                return filterLimitOffset(M, self.db, self.gpa, self.where_clause, self.where_vals.items, self.limit_val.?, self.offset_val.?);
            }
            if (hw and ho) {
                var list = std.ArrayList(RowType(M)).empty;
                const sql = std.fmt.allocPrintSentinel(self.gpa, "{s} WHERE {s} ORDER BY {s}", .{ M.select_all_sql, self.where_clause, self.order_clause }, 0) catch return error.AllocatorFailed;
                defer self.gpa.free(@constCast(sql));
                var stmt = self.db.prepare(sql) catch return error.PrepareFailed;
                defer stmt.finalize();
                for (self.where_vals.items, 0..) |v, i| stmt.bind(v, @intCast(i + 1)) catch return error.BindFailed;
                while (stmt.step() catch return error.StepFailed) {
                    const row = try readRow(M, &stmt, self.gpa);
                    list.append(self.gpa, row) catch return error.AllocatorFailed;
                }
                return list;
            }
            if (ho) return order(M, self.db, self.gpa, self.order_clause);
            if (hw) return filter(M, self.db, self.gpa, self.where_clause, self.where_vals.items);
            return all(M, self.db, self.gpa);
        }
    };
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

/// FILTER with WHERE, ORDER BY, LIMIT, and OFFSET.
/// Caller owns the rows and their text memory — call freeRow on each when done.
pub fn filterOrderLimitOffset(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, where: [:0]const u8, values: []const sqlite.Value, order_by: []const u8, limit: u64, offset: u64) QueryError!std.ArrayList(RowType(M)) {
    var list = std.ArrayList(RowType(M)).empty;
    const has_where = where.len > 0;
    const has_order = order_by.len > 0;
    var frags = std.ArrayList(u8).empty;
    defer frags.deinit(gpa);
    frags.appendSlice(gpa, M.select_all_sql) catch return error.AllocatorFailed;
    if (has_where) {
        frags.appendSlice(gpa, " WHERE ") catch return error.AllocatorFailed;
        frags.appendSlice(gpa, where) catch return error.AllocatorFailed;
    }
    if (has_order) {
        frags.appendSlice(gpa, " ORDER BY ") catch return error.AllocatorFailed;
        frags.appendSlice(gpa, order_by) catch return error.AllocatorFailed;
    }
    frags.appendSlice(gpa, " LIMIT ? OFFSET ?") catch return error.AllocatorFailed;
    const alloc_sql = frags.toOwnedSliceSentinel(gpa, 0) catch return error.AllocatorFailed;
    defer gpa.free(alloc_sql);
    var stmt = db.prepare(alloc_sql) catch return error.PrepareFailed;
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
    log.info("filtered {d} rows from {s} (order={s}, limit={d}, offset={d})", .{ list.items.len, M.table_name, order_by, limit, offset });
    return list;
}

/// SELECT first matching row. Returns null if no match.
/// Caller owns the row's text memory — call freeRow when done.
pub fn first(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, where: [:0]const u8, values: []const sqlite.Value) QueryError!?RowType(M) {
    var rows = try filterLimitOffset(M, db, gpa, where, values, 1, 0);
    if (rows.items.len == 0) return null;
    const row = rows.items[0];
    rows.deinit(gpa);
    return row;
}

/// INSERT or UPDATE a record. If row[0] (id) is 0, inserts; otherwise updates.
/// Returns the rowid. On insert, row[0] is updated with the new id.
pub fn save(comptime M: type, db: *sqlite.Db, gpa: std.mem.Allocator, row: *RowType(M)) QueryError!i64 {
    _ = gpa;
    const id: i64 = row[0];
    if (id == 0) {
        // INSERT — skip id field (auto-increment)
        var stmt = db.prepare(M.insert_sql) catch return error.PrepareFailed;
        defer stmt.finalize();
        inline for (1..M.fields_len) |i| {
            const FieldType = @typeInfo(RowType(M)).@"struct".field_types[i];
            if (FieldType == i64) {
                stmt.bind(.{ .int = row[i] }, @intCast(i)) catch return error.BindFailed;
            } else if (FieldType == f64) {
                stmt.bind(.{ .float = row[i] }, @intCast(i)) catch return error.BindFailed;
            } else if (FieldType == []const u8) {
                stmt.bind(.{ .text = row[i] }, @intCast(i)) catch return error.BindFailed;
            } else if (FieldType == bool) {
                stmt.bind(.{ .int = if (row[i]) @as(i64, 1) else 0 }, @intCast(i)) catch return error.BindFailed;
            }
        }
        _ = stmt.step() catch return error.StepFailed;
        const new_id = db.lastInsertRowId();
        row[0] = new_id;
        log.info("saved new record in {s}: rowid={d}", .{ M.table_name, new_id });
        return new_id;
    } else {
        // UPDATE
        const values = blk: {
            var arr: [M.fields_len - 1]sqlite.Value = undefined;
            inline for (1..M.fields_len) |i| {
                const FieldType = @typeInfo(RowType(M)).@"struct".field_types[i];
                arr[i - 1] = if (FieldType == i64) .{ .int = row[i] } else if (FieldType == f64) .{ .float = row[i] } else if (FieldType == []const u8) .{ .text = row[i] } else if (FieldType == bool) .{ .int = if (row[i]) 1 else 0 } else .{ .int = 0 };
            }
            break :blk &arr;
        };
        try updateById(M, db, id, values);
        return id;
    }
}

test {
    std.testing.refAllDecls(@This());
}
