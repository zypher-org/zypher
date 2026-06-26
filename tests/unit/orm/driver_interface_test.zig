const std = @import("std");
const zypher = @import("zypher");
const interface = zypher.orm.driver.interface;

test "hand-rolled mock struct satisfies RelationalDb and dispatches correctly" {
    const MockDb = struct {
        exec_called: bool = false,
        last_exec_sql: [:0]const u8 = "",
        prepare_called: bool = false,
        last_prepare_sql: [:0]const u8 = "",

        pub fn exec(self: *@This(), sql: [:0]const u8) interface.DbError!void {
            self.exec_called = true;
            self.last_exec_sql = sql;
        }

        pub fn prepare(self: *@This(), sql: [:0]const u8) interface.DbError!interface.AnyStmt {
            self.prepare_called = true;
            self.last_prepare_sql = sql;
            return .{
                .ptr = @ptrCast(self),
                .vtable = &.{
                    .bind = struct {
                        fn f(ptr: *anyopaque, value: interface.Value, idx: c_int) interface.DbError!void {
                            _ = ptr;
                            _ = value;
                            _ = idx;
                        }
                    }.f,
                    .step = struct {
                        fn f(ptr: *anyopaque) interface.DbError!bool {
                            _ = ptr;
                            return false;
                        }
                    }.f,
                    .column = struct {
                        fn f(ptr: *anyopaque, kind: interface.ColumnType, idx: c_int) interface.DbError!interface.Value {
                            _ = ptr;
                            _ = kind;
                            _ = idx;
                            return .{ .null = {} };
                        }
                    }.f,
                    .columnType = struct {
                        fn f(ptr: *anyopaque, idx: c_int) interface.DbError!interface.ColumnType {
                            _ = ptr;
                            _ = idx;
                            return .null;
                        }
                    }.f,
                    .reset = struct {
                        fn f(ptr: *anyopaque) interface.DbError!void {
                            _ = ptr;
                        }
                    }.f,
                    .finalize = struct {
                        fn f(ptr: *anyopaque) void {
                            _ = ptr;
                        }
                    }.f,
                },
            };
        }

        pub fn lastInsertId(_: *@This()) i64 {
            return 42;
        }

        pub fn changes(_: *@This()) i64 {
            return 1;
        }

        pub fn close(self: *@This()) void {
            self.exec_called = false;
        }

        pub fn dialect(_: *@This()) interface.Dialect {
            return interface.SqliteDialect;
        }
    };

    var mock = MockDb{};
    var db: interface.RelationalDb = .{
        .ptr = @ptrCast(&mock),
        .vtable = &.{
            .exec = struct {
                fn f(ptr: *anyopaque, sql: [:0]const u8) interface.DbError!void {
                    var m: *MockDb = @ptrCast(@alignCast(ptr));
                    try m.exec(sql);
                }
            }.f,
            .prepare = struct {
                fn f(ptr: *anyopaque, sql: [:0]const u8) interface.DbError!interface.AnyStmt {
                    var m: *MockDb = @ptrCast(@alignCast(ptr));
                    return try m.prepare(sql);
                }
            }.f,
            .lastInsertId = struct {
                fn f(ptr: *anyopaque) i64 {
                    var m: *MockDb = @ptrCast(@alignCast(ptr));
                    return m.lastInsertId();
                }
            }.f,
            .changes = struct {
                fn f(ptr: *anyopaque) i64 {
                    var m: *MockDb = @ptrCast(@alignCast(ptr));
                    return m.changes();
                }
            }.f,
            .close = struct {
                fn f(ptr: *anyopaque) void {
                    var m: *MockDb = @ptrCast(@alignCast(ptr));
                    m.close();
                }
            }.f,
            .dialect = struct {
                fn f(ptr: *anyopaque) interface.Dialect {
                    var m: *MockDb = @ptrCast(@alignCast(ptr));
                    return m.dialect();
                }
            }.f,
        },
    };

    try db.exec("CREATE TABLE test (id INT)");
    try std.testing.expect(mock.exec_called);
    try std.testing.expectEqualStrings("CREATE TABLE test (id INT)", mock.last_exec_sql);

    var stmt = try db.prepare("SELECT * FROM test");
    try std.testing.expect(mock.prepare_called);
    try std.testing.expectEqualStrings("SELECT * FROM test", mock.last_prepare_sql);

    try std.testing.expect(!try stmt.step());
    try std.testing.expectEqual(@as(i64, 42), db.lastInsertId());
    try std.testing.expectEqual(@as(i64, 1), db.changes());
    const d = db.dialect();
    try std.testing.expectEqualStrings("INTEGER PRIMARY KEY AUTOINCREMENT", d.pk_type);

    db.close();
}

test "AnyStmt bind, step, column, finalize dispatch through vtable" {
    const MockStmt = struct {
        bind_called: bool = false,
        step_called: bool = false,
        finalize_called: bool = false,
        last_value: interface.Value = .{ .null = {} },
        last_idx: c_int = 0,

        pub fn bind(self: *@This(), value: interface.Value, idx: c_int) interface.DbError!void {
            self.bind_called = true;
            self.last_value = value;
            self.last_idx = idx;
        }

        pub fn step(self: *@This()) interface.DbError!bool {
            self.step_called = true;
            return true;
        }

        pub fn column(_: *@This(), kind: interface.ColumnType, idx: c_int) interface.DbError!interface.Value {
            _ = kind;
            if (idx == 0) return .{ .int = 99 };
            return .{ .null = {} };
        }

        pub fn columnType(self: *@This(), idx: c_int) interface.DbError!interface.ColumnType {
            _ = self;
            _ = idx;
            return .integer;
        }

        pub fn reset(_: *@This()) interface.DbError!void {}

        pub fn finalize(self: *@This()) void {
            self.finalize_called = true;
        }
    };

    var mock = MockStmt{};
    var stmt: interface.AnyStmt = .{
        .ptr = @ptrCast(&mock),
        .vtable = &.{
            .bind = struct {
                fn f(ptr: *anyopaque, value: interface.Value, idx: c_int) interface.DbError!void {
                    var m: *MockStmt = @ptrCast(@alignCast(ptr));
                    try m.bind(value, idx);
                }
            }.f,
            .step = struct {
                fn f(ptr: *anyopaque) interface.DbError!bool {
                    var m: *MockStmt = @ptrCast(@alignCast(ptr));
                    return try m.step();
                }
            }.f,
            .column = struct {
                fn f(ptr: *anyopaque, kind: interface.ColumnType, idx: c_int) interface.DbError!interface.Value {
                    var m: *MockStmt = @ptrCast(@alignCast(ptr));
                    return try m.column(kind, idx);
                }
            }.f,
            .columnType = struct {
                fn f(ptr: *anyopaque, idx: c_int) interface.DbError!interface.ColumnType {
                    var m: *MockStmt = @ptrCast(@alignCast(ptr));
                    return try m.columnType(idx);
                }
            }.f,
            .reset = struct {
                fn f(ptr: *anyopaque) interface.DbError!void {
                    _ = ptr;
                }
            }.f,
            .finalize = struct {
                fn f(ptr: *anyopaque) void {
                    var m: *MockStmt = @ptrCast(@alignCast(ptr));
                    m.finalize();
                }
            }.f,
        },
    };

    try stmt.bind(.{ .int = 42 }, 1);
    try std.testing.expect(mock.bind_called);
    try std.testing.expectEqual(@as(c_int, 1), mock.last_idx);

    const has_row = try stmt.step();
    try std.testing.expect(mock.step_called);
    try std.testing.expect(has_row);

    const val = try stmt.column(.integer, 0);
    try std.testing.expectEqual(@as(i64, 99), val.int);

    const col_type = try stmt.columnType(0);
    try std.testing.expectEqual(.integer, col_type);

    stmt.finalize();
    try std.testing.expect(mock.finalize_called);
}

test "SqliteDialect properties are correct" {
    const dialect = interface.SqliteDialect;
    try std.testing.expectEqualStrings("INTEGER PRIMARY KEY AUTOINCREMENT", dialect.pk_type);
    try std.testing.expectEqualStrings("REAL", dialect.float_type);
    try std.testing.expectEqualStrings("INTEGER", dialect.bool_type);
    try std.testing.expectEqualStrings("TEXT", dialect.text_type);
    try std.testing.expectEqualStrings("strftime('%s','now')", dialect.timestamp_now);

    var buf: [16]u8 = undefined;
    const ph1 = dialect.placeholder(1, &buf);
    try std.testing.expectEqualStrings("?", ph1);
    const ph2 = dialect.placeholder(2, &buf);
    try std.testing.expectEqualStrings("?", ph2);
}

test "PostgresDialect properties are correct" {
    const dialect = interface.PostgresDialect;
    try std.testing.expectEqualStrings("BIGSERIAL PRIMARY KEY", dialect.pk_type);
    try std.testing.expectEqualStrings("DOUBLE PRECISION", dialect.float_type);
    try std.testing.expectEqualStrings("BOOLEAN", dialect.bool_type);
    try std.testing.expectEqualStrings("TEXT", dialect.text_type);
    try std.testing.expectEqualStrings("EXTRACT(EPOCH FROM NOW())::BIGINT", dialect.timestamp_now);

    var buf: [16]u8 = undefined;
    const ph1 = dialect.placeholder(1, &buf);
    try std.testing.expectEqualStrings("$1", ph1);
    const ph12 = dialect.placeholder(12, &buf);
    try std.testing.expectEqualStrings("$12", ph12);
}

test "MysqlDialect properties are correct" {
    const dialect = interface.MysqlDialect;
    try std.testing.expectEqualStrings("INT AUTO_INCREMENT PRIMARY KEY", dialect.pk_type);
    try std.testing.expectEqualStrings("DOUBLE", dialect.float_type);
    try std.testing.expectEqualStrings("TINYINT(1)", dialect.bool_type);
    try std.testing.expectEqualStrings("TEXT", dialect.text_type);
    try std.testing.expectEqualStrings("UNIX_TIMESTAMP()", dialect.timestamp_now);

    var buf: [16]u8 = undefined;
    const ph1 = dialect.placeholder(1, &buf);
    try std.testing.expectEqualStrings("?", ph1);
    const ph2 = dialect.placeholder(2, &buf);
    try std.testing.expectEqualStrings("?", ph2);
}

test "Value tagged union works correctly" {
    const v_int = interface.Value{ .int = 42 };
    const v_float = interface.Value{ .float = 3.14 };
    const v_text = interface.Value{ .text = "hello" };
    const v_null = interface.Value{ .null = {} };

    try std.testing.expectEqual(@as(i64, 42), v_int.int);
    try std.testing.expectEqual(@as(f64, 3.14), v_float.float);
    try std.testing.expectEqualStrings("hello", v_text.text);
    try std.testing.expect(v_null == .null);
}

test "ColumnType enum values match expected" {
    try std.testing.expectEqual(@intFromEnum(interface.ColumnType.integer), 0);
    try std.testing.expectEqual(@intFromEnum(interface.ColumnType.float), 1);
    try std.testing.expectEqual(@intFromEnum(interface.ColumnType.text), 2);
    try std.testing.expectEqual(@intFromEnum(interface.ColumnType.blob), 3);
    try std.testing.expectEqual(@intFromEnum(interface.ColumnType.null), 4);
}

test "DbError error set includes all expected variants" {
    const errs = [_]interface.DbError{
        error.OpenFailed,
        error.ExecFailed,
        error.PrepareFailed,
        error.StepFailed,
        error.BindFailed,
        error.ColumnFailed,
        error.ConstraintViolation,
        error.UnexpectedResult,
        error.AllocatorFailed,
    };
    try std.testing.expect(errs.len == 9);
}
