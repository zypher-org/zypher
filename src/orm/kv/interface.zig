const std = @import("std");

pub const KVError = error{
    OpenFailed,
    GetFailed,
    SetFailed,
    DelFailed,
    ExpireFailed,
    HashFailed,
    ListFailed,
    AllocatorFailed,
};

pub const KVStore = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        get: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8) KVError!?[]const u8,
        set: *const fn (ptr: *anyopaque, key: []const u8, value: []const u8) KVError!void,
        del: *const fn (ptr: *anyopaque, key: []const u8) KVError!void,
        exists: *const fn (ptr: *anyopaque, key: []const u8) KVError!bool,
        expire: *const fn (ptr: *anyopaque, key: []const u8, seconds: i64) KVError!void,
        hset: *const fn (ptr: *anyopaque, key: []const u8, field: []const u8, value: []const u8) KVError!void,
        hget: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8, field: []const u8) KVError!?[]const u8,
        lpush: *const fn (ptr: *anyopaque, key: []const u8, value: []const u8) KVError!void,
        lrange: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8, start: i64, stop: i64) KVError![]const []const u8,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn get(self: KVStore, gpa: std.mem.Allocator, key: []const u8) KVError!?[]const u8 {
        return try self.vtable.get(self.ptr, gpa, key);
    }

    pub fn set(self: KVStore, key: []const u8, value: []const u8) KVError!void {
        try self.vtable.set(self.ptr, key, value);
    }

    pub fn del(self: KVStore, key: []const u8) KVError!void {
        try self.vtable.del(self.ptr, key);
    }

    pub fn exists(self: KVStore, key: []const u8) KVError!bool {
        return try self.vtable.exists(self.ptr, key);
    }

    pub fn expire(self: KVStore, key: []const u8, seconds: i64) KVError!void {
        try self.vtable.expire(self.ptr, key, seconds);
    }

    pub fn hset(self: KVStore, key: []const u8, field: []const u8, value: []const u8) KVError!void {
        try self.vtable.hset(self.ptr, key, field, value);
    }

    pub fn hget(self: KVStore, gpa: std.mem.Allocator, key: []const u8, field: []const u8) KVError!?[]const u8 {
        return try self.vtable.hget(self.ptr, gpa, key, field);
    }

    pub fn lpush(self: KVStore, key: []const u8, value: []const u8) KVError!void {
        try self.vtable.lpush(self.ptr, key, value);
    }

    pub fn lrange(self: KVStore, gpa: std.mem.Allocator, key: []const u8, start: i64, stop: i64) KVError![]const []const u8 {
        return try self.vtable.lrange(self.ptr, gpa, key, start, stop);
    }

    pub fn close(self: KVStore) void {
        self.vtable.close(self.ptr);
    }
};

test {
    std.testing.refAllDecls(@This());
}
