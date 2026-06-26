const std = @import("std");

pub const BsonValue = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
    oid: [12]u8,
    null: void,
    doc: *std.StringHashMap(BsonValue),
    arr: *std.ArrayList(BsonValue),
};

pub const Document = std.StringHashMap(BsonValue);

pub const ObjectId = [12]u8;

pub const Filter = Document;

pub const DocumentError = error{
    OpenFailed,
    InsertFailed,
    FindFailed,
    UpdateFailed,
    DeleteFailed,
    CursorFailed,
    AllocatorFailed,
};

pub const Collection = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        insertOne: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, doc: *const Document) DocumentError!ObjectId,
        findOne: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, filter: *const Filter) DocumentError!?Document,
        updateOne: *const fn (ptr: *anyopaque, filter: *const Filter, update: *const Document) DocumentError!void,
        deleteOne: *const fn (ptr: *anyopaque, filter: *const Filter) DocumentError!void,
        countDocuments: *const fn (ptr: *anyopaque, filter: *const Filter) DocumentError!u64,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn insertOne(self: Collection, gpa: std.mem.Allocator, doc: *const Document) DocumentError!ObjectId {
        return try self.vtable.insertOne(self.ptr, gpa, doc);
    }

    pub fn findOne(self: Collection, gpa: std.mem.Allocator, filter: *const Filter) DocumentError!?Document {
        return try self.vtable.findOne(self.ptr, gpa, filter);
    }

    pub fn updateOne(self: Collection, filter: *const Filter, update: *const Document) DocumentError!void {
        try self.vtable.updateOne(self.ptr, filter, update);
    }

    pub fn deleteOne(self: Collection, filter: *const Filter) DocumentError!void {
        try self.vtable.deleteOne(self.ptr, filter);
    }

    pub fn countDocuments(self: Collection, filter: *const Filter) DocumentError!u64 {
        return try self.vtable.countDocuments(self.ptr, filter);
    }

    pub fn close(self: Collection) void {
        self.vtable.close(self.ptr);
    }
};

pub const DocumentStore = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        collection: *const fn (ptr: *anyopaque, name: []const u8) Collection,
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn collection(self: DocumentStore, name: []const u8) Collection {
        return self.vtable.collection(self.ptr, name);
    }

    pub fn close(self: DocumentStore) void {
        self.vtable.close(self.ptr);
    }
};

test {
    std.testing.refAllDecls(@This());
}
