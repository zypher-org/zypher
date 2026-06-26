const std = @import("std");
const build_config = @import("build_config");
const zypher = @import("zypher");
const doc_iface = zypher.orm.document.interface;

test "DocumentStore vtable dispatching works through mock" {
    const MockCollection = struct {
        insert_count: usize = 0,
        find_count: usize = 0,
        update_count: usize = 0,
        delete_count: usize = 0,
        count_result: u64 = 0,

        pub fn insertOne(self: *@This(), gpa: std.mem.Allocator, doc: *const doc_iface.Document) doc_iface.DocumentError!doc_iface.ObjectId {
            _ = gpa;
            _ = doc;
            self.insert_count += 1;
            return [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
        }

        pub fn findOne(self: *@This(), gpa: std.mem.Allocator, filter: *const doc_iface.Filter) doc_iface.DocumentError!?doc_iface.Document {
            _ = filter;
            self.find_count += 1;
            var result = doc_iface.Document.init(gpa);
            result.put("_id", .{ .oid = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } }) catch return error.AllocatorFailed;
            result.put("name", .{ .string = "zig" }) catch return error.AllocatorFailed;
            result.put("age", .{ .int = 3 }) catch return error.AllocatorFailed;
            return result;
        }

        pub fn updateOne(self: *@This(), filter: *const doc_iface.Filter, update: *const doc_iface.Document) doc_iface.DocumentError!void {
            _ = filter;
            _ = update;
            self.update_count += 1;
        }

        pub fn deleteOne(self: *@This(), filter: *const doc_iface.Filter) doc_iface.DocumentError!void {
            _ = filter;
            self.delete_count += 1;
        }

        pub fn countDocuments(self: *@This(), filter: *const doc_iface.Filter) doc_iface.DocumentError!u64 {
            _ = filter;
            return self.count_result;
        }

        pub fn close(_: *@This()) void {}
    };

    const MockStore = struct {
        collection_called: bool = false,
        close_called: bool = false,
        last_col_name: []const u8 = "",
        mock_col: MockCollection = .{},

        pub fn collection(self: *@This(), name: []const u8) doc_iface.Collection {
            self.collection_called = true;
            self.last_col_name = name;
            return .{
                .ptr = @ptrCast(&self.mock_col),
                .vtable = &.{
                    .insertOne = struct {
                        fn f(ptr: *anyopaque, gpa: std.mem.Allocator, doc: *const doc_iface.Document) doc_iface.DocumentError!doc_iface.ObjectId {
                            var col: *MockCollection = @ptrCast(@alignCast(ptr));
                            return try col.insertOne(gpa, doc);
                        }
                    }.f,
                    .findOne = struct {
                        fn f(ptr: *anyopaque, gpa: std.mem.Allocator, filter: *const doc_iface.Filter) doc_iface.DocumentError!?doc_iface.Document {
                            var col: *MockCollection = @ptrCast(@alignCast(ptr));
                            return try col.findOne(gpa, filter);
                        }
                    }.f,
                    .updateOne = struct {
                        fn f(ptr: *anyopaque, filter: *const doc_iface.Filter, update: *const doc_iface.Document) doc_iface.DocumentError!void {
                            var col: *MockCollection = @ptrCast(@alignCast(ptr));
                            try col.updateOne(filter, update);
                        }
                    }.f,
                    .deleteOne = struct {
                        fn f(ptr: *anyopaque, filter: *const doc_iface.Filter) doc_iface.DocumentError!void {
                            var col: *MockCollection = @ptrCast(@alignCast(ptr));
                            try col.deleteOne(filter);
                        }
                    }.f,
                    .countDocuments = struct {
                        fn f(ptr: *anyopaque, filter: *const doc_iface.Filter) doc_iface.DocumentError!u64 {
                            var col: *MockCollection = @ptrCast(@alignCast(ptr));
                            return try col.countDocuments(filter);
                        }
                    }.f,
                    .close = struct {
                        fn f(ptr: *anyopaque) void {
                            var col: *MockCollection = @ptrCast(@alignCast(ptr));
                            col.close();
                        }
                    }.f,
                },
            };
        }

        pub fn close(self: *@This()) void {
            self.close_called = true;
        }
    };

    var mock = MockStore{};
    var store: doc_iface.DocumentStore = .{
        .ptr = @ptrCast(&mock),
        .vtable = &.{
            .collection = struct {
                fn f(ptr: *anyopaque, name: []const u8) doc_iface.Collection {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    return m.collection(name);
                }
            }.f,
            .close = struct {
                fn f(ptr: *anyopaque) void {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    m.close();
                }
            }.f,
        },
    };

    const col = store.collection("test_col");
    try std.testing.expect(mock.collection_called);
    try std.testing.expectEqualStrings("test_col", mock.last_col_name);

    var doc = doc_iface.Document.init(std.testing.allocator);
    defer {
        var d = doc;
        d.deinit();
    }
    try doc.put("name", .{ .string = "zig" });
    try doc.put("age", .{ .int = 3 });

    const oid = try col.insertOne(std.testing.allocator, &doc);
    try std.testing.expectEqual(@as(usize, 1), mock.mock_col.insert_count);
    try std.testing.expectEqual(@as(u8, 1), oid[0]);
    try std.testing.expectEqual(@as(u8, 12), oid[11]);

    var filter = doc_iface.Document.init(std.testing.allocator);
    defer {
        var f = filter;
        f.deinit();
    }
    try filter.put("_id", .{ .oid = oid });

    const found = try col.findOne(std.testing.allocator, &filter);
    try std.testing.expectEqual(@as(usize, 1), mock.mock_col.find_count);
    try std.testing.expect(found != null);
    if (found) |f| {
        defer {
            var ff = f;
            ff.deinit();
        }
        const name_val = f.get("name");
        try std.testing.expect(name_val != null);
        if (name_val) |nv| {
            try std.testing.expectEqualStrings("zig", nv.string);
        }
        const age_val = f.get("age");
        try std.testing.expect(age_val != null);
        if (age_val) |av| {
            try std.testing.expectEqual(@as(i64, 3), av.int);
        }
    }

    var update = doc_iface.Document.init(std.testing.allocator);
    defer {
        var u = update;
        u.deinit();
    }
    try update.put("age", .{ .int = 4 });

    try col.updateOne(&filter, &update);
    try std.testing.expectEqual(@as(usize, 1), mock.mock_col.update_count);

    try col.deleteOne(&filter);
    try std.testing.expectEqual(@as(usize, 1), mock.mock_col.delete_count);

    col.close();
    store.close();
    try std.testing.expect(mock.close_called);
}

test "BsonValue tagged union variants work correctly" {
    const v_string = doc_iface.BsonValue{ .string = "hello" };
    const v_int = doc_iface.BsonValue{ .int = 42 };
    const v_float = doc_iface.BsonValue{ .float = 3.14 };
    const v_bool = doc_iface.BsonValue{ .bool = true };
    const v_oid = doc_iface.BsonValue{ .oid = [_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } };
    const v_null = doc_iface.BsonValue{ .null = {} };

    try std.testing.expectEqualStrings("hello", v_string.string);
    try std.testing.expectEqual(@as(i64, 42), v_int.int);
    try std.testing.expectEqual(@as(f64, 3.14), v_float.float);
    try std.testing.expectEqual(true, v_bool.bool);
    try std.testing.expectEqual(@as(u8, 1), v_oid.oid[0]);
    try std.testing.expect(v_null == .null);
}

test "Document put and get round-trips through StringHashMap" {
    var doc = doc_iface.Document.init(std.testing.allocator);
    defer {
        var d = doc;
        d.deinit();
    }

    try doc.put("name", .{ .string = "test" });
    try doc.put("age", .{ .int = 10 });
    try doc.put("active", .{ .bool = true });

    const name = doc.get("name");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("test", name.?.string);

    const age = doc.get("age");
    try std.testing.expect(age != null);
    try std.testing.expectEqual(@as(i64, 10), age.?.int);

    const active = doc.get("active");
    try std.testing.expect(active != null);
    try std.testing.expectEqual(true, active.?.bool);

    const missing = doc.get("nonexistent");
    try std.testing.expect(missing == null);
}

test "ObjectId is a 12-byte array" {
    const oid: doc_iface.ObjectId = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
    try std.testing.expectEqual(@as(usize, 12), oid.len);
    try std.testing.expectEqual(@as(u8, 0), oid[0]);
    try std.testing.expectEqual(@as(u8, 11), oid[11]);
}

test "DocumentError error set includes all expected variants" {
    const errs = [_]doc_iface.DocumentError{
        error.OpenFailed,
        error.InsertFailed,
        error.FindFailed,
        error.UpdateFailed,
        error.DeleteFailed,
        error.CursorFailed,
        error.AllocatorFailed,
    };
    try std.testing.expect(errs.len == 7);
}

test "Filter is an alias for Document" {
    try std.testing.expect(doc_iface.Filter == doc_iface.Document);
}
