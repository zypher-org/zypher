const std = @import("std");
const build_config = @import("build_config");
const zypher = @import("zypher");
const kv_iface = zypher.orm.kv.interface;

test "KVStore vtable dispatching works through mock" {
    const MockStore = struct {
        const Self = @This();
        get_called: bool = false,
        set_called: bool = false,
        del_called: bool = false,
        exists_called: bool = false,
        expire_called: bool = false,
        hset_called: bool = false,
        hget_called: bool = false,
        lpush_called: bool = false,
        lrange_called: bool = false,
        close_called: bool = false,
        last_key: []const u8 = "",
        last_value: []const u8 = "",
        last_field: []const u8 = "",
        stored: std.StringHashMap([]const u8) = undefined,
        alloc: std.mem.Allocator = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .stored = std.StringHashMap([]const u8).init(allocator),
                .alloc = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.stored.iterator();
            while (it.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
                self.alloc.free(entry.value_ptr.*);
            }
            self.stored.deinit();
        }

        pub fn get(self: *Self, gpa: std.mem.Allocator, key: []const u8) kv_iface.KVError!?[]const u8 {
            _ = gpa;
            self.get_called = true;
            self.last_key = key;
            const val = self.stored.get(key);
            return if (val) |v| self.alloc.dupe(u8, v) catch return error.AllocatorFailed else null;
        }

        pub fn set(self: *Self, key: []const u8, value: []const u8) kv_iface.KVError!void {
            self.set_called = true;
            self.last_key = key;
            self.last_value = value;
            const owned_key = self.alloc.dupe(u8, key) catch return error.AllocatorFailed;
            errdefer self.alloc.free(owned_key);
            const owned_val = self.alloc.dupe(u8, value) catch return error.AllocatorFailed;
            errdefer self.alloc.free(owned_val);
            self.stored.put(owned_key, owned_val) catch {
                self.alloc.free(owned_key);
                self.alloc.free(owned_val);
                return error.AllocatorFailed;
            };
        }

        pub fn del(self: *Self, key: []const u8) kv_iface.KVError!void {
            self.del_called = true;
            self.last_key = key;
            if (self.stored.fetchRemove(key)) |entry| {
                self.alloc.free(entry.key);
                self.alloc.free(entry.value);
            }
        }

        pub fn exists(self: *Self, key: []const u8) kv_iface.KVError!bool {
            self.exists_called = true;
            self.last_key = key;
            return self.stored.contains(key);
        }

        pub fn expire(self: *Self, key: []const u8, seconds: i64) kv_iface.KVError!void {
            _ = seconds;
            self.expire_called = true;
            self.last_key = key;
        }

        pub fn hset(self: *Self, key: []const u8, field: []const u8, value: []const u8) kv_iface.KVError!void {
            self.hset_called = true;
            self.last_key = key;
            self.last_field = field;
            self.last_value = value;
        }

        pub fn hget(self: *Self, gpa: std.mem.Allocator, key: []const u8, field: []const u8) kv_iface.KVError!?[]const u8 {
            _ = gpa;
            self.hget_called = true;
            self.last_key = key;
            self.last_field = field;
            return null;
        }

        pub fn lpush(self: *Self, key: []const u8, value: []const u8) kv_iface.KVError!void {
            self.lpush_called = true;
            self.last_key = key;
            self.last_value = value;
        }

        pub fn lrange(self: *Self, gpa: std.mem.Allocator, key: []const u8, start: i64, stop: i64) kv_iface.KVError![]const []const u8 {
            _ = gpa;
            _ = start;
            _ = stop;
            self.lrange_called = true;
            self.last_key = key;
            return &[_][]const u8{};
        }

        pub fn close(self: *Self) void {
            self.close_called = true;
        }
    };

    var mock = MockStore.init(std.testing.allocator);
    defer mock.deinit();

    var store: kv_iface.KVStore = .{
        .ptr = @ptrCast(&mock),
        .vtable = &.{
            .get = struct {
                fn f(ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8) kv_iface.KVError!?[]const u8 {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    return try m.get(gpa, key);
                }
            }.f,
            .set = struct {
                fn f(ptr: *anyopaque, key: []const u8, value: []const u8) kv_iface.KVError!void {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    try m.set(key, value);
                }
            }.f,
            .del = struct {
                fn f(ptr: *anyopaque, key: []const u8) kv_iface.KVError!void {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    try m.del(key);
                }
            }.f,
            .exists = struct {
                fn f(ptr: *anyopaque, key: []const u8) kv_iface.KVError!bool {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    return try m.exists(key);
                }
            }.f,
            .expire = struct {
                fn f(ptr: *anyopaque, key: []const u8, seconds: i64) kv_iface.KVError!void {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    try m.expire(key, seconds);
                }
            }.f,
            .hset = struct {
                fn f(ptr: *anyopaque, key: []const u8, field: []const u8, value: []const u8) kv_iface.KVError!void {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    try m.hset(key, field, value);
                }
            }.f,
            .hget = struct {
                fn f(ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8, field: []const u8) kv_iface.KVError!?[]const u8 {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    return try m.hget(gpa, key, field);
                }
            }.f,
            .lpush = struct {
                fn f(ptr: *anyopaque, key: []const u8, value: []const u8) kv_iface.KVError!void {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    try m.lpush(key, value);
                }
            }.f,
            .lrange = struct {
                fn f(ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8, start: i64, stop: i64) kv_iface.KVError![]const []const u8 {
                    var m: *MockStore = @ptrCast(@alignCast(ptr));
                    return try m.lrange(gpa, key, start, stop);
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

    try store.set("key", "value");
    try std.testing.expect(mock.set_called);
    try std.testing.expectEqualStrings("key", mock.last_key);
    try std.testing.expectEqualStrings("value", mock.last_value);

    const val = try store.get(std.testing.allocator, "key");
    defer if (val) |v| std.testing.allocator.free(v);
    try std.testing.expect(mock.get_called);
    try std.testing.expect(val != null);

    const exists = try store.exists("key");
    try std.testing.expect(mock.exists_called);
    try std.testing.expect(exists);

    try store.del("key");
    try std.testing.expect(mock.del_called);

    try store.expire("key", 60);
    try std.testing.expect(mock.expire_called);

    try store.hset("myhash", "field", "val");
    try std.testing.expect(mock.hset_called);
    try std.testing.expectEqualStrings("field", mock.last_field);

    _ = try store.hget(std.testing.allocator, "myhash", "field");
    try std.testing.expect(mock.hget_called);

    try store.lpush("mylist", "item");
    try std.testing.expect(mock.lpush_called);

    _ = try store.lrange(std.testing.allocator, "mylist", 0, -1);
    try std.testing.expect(mock.lrange_called);

    store.close();
    try std.testing.expect(mock.close_called);
}

test "KVError error set includes all expected variants" {
    const errs = [_]kv_iface.KVError{
        error.OpenFailed,
        error.GetFailed,
        error.SetFailed,
        error.DelFailed,
        error.ExpireFailed,
        error.HashFailed,
        error.ListFailed,
        error.AllocatorFailed,
    };
    try std.testing.expect(errs.len == 8);
}
