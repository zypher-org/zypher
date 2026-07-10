const std = @import("std");
const build_config = @import("build_config");
const iface = @import("interface.zig");

pub const enabled = build_config.has_mongodb;

pub const Document = iface.Document;
pub const Filter = iface.Filter;
pub const ObjectId = iface.ObjectId;
pub const DocumentError = iface.DocumentError;
pub const Collection = iface.Collection;

pub const c = if (build_config.has_mongodb) struct {
    pub const mongoc_client_t = opaque {};
    pub const mongoc_collection_t = opaque {};
    pub const mongoc_cursor_t = opaque {};
    pub const bson_t = opaque {};

    pub const bson_iter_t = extern struct {
        _data: [128]u8 align(8),
    };

    pub const bson_error_t = extern struct {
        domain: u32,
        code: u32,
        message: [504]u8,
    };

    pub const bson_oid_t = extern struct {
        bytes: [12]u8,
    };

    pub const BSON_TYPE_EOD: c_int = 0;
    pub const BSON_TYPE_DOUBLE: c_int = 1;
    pub const BSON_TYPE_UTF8: c_int = 2;
    pub const BSON_TYPE_DOCUMENT: c_int = 3;
    pub const BSON_TYPE_ARRAY: c_int = 4;
    pub const BSON_TYPE_BOOL: c_int = 8;
    pub const BSON_TYPE_NULL: c_int = 10;
    pub const BSON_TYPE_OID: c_int = 7;
    pub const BSON_TYPE_INT32: c_int = 16;
    pub const BSON_TYPE_INT64: c_int = 18;

    pub extern fn mongoc_init() void;
    pub extern fn mongoc_cleanup() void;
    pub extern fn mongoc_client_new(uri: [*:0]const u8) ?*mongoc_client_t;
    pub extern fn mongoc_client_destroy(client: ?*mongoc_client_t) void;
    pub extern fn mongoc_client_get_collection(
        client: ?*mongoc_client_t,
        db: [*:0]const u8,
        collection: [*:0]const u8,
    ) ?*mongoc_collection_t;
    pub extern fn mongoc_collection_destroy(collection: ?*mongoc_collection_t) void;
    pub extern fn mongoc_collection_insert_one(
        collection: ?*mongoc_collection_t,
        document: ?*const bson_t,
        opts: ?*const bson_t,
        reply: ?*bson_t,
        err: ?*bson_error_t,
    ) bool;
    pub extern fn mongoc_collection_find_with_opts(
        collection: ?*mongoc_collection_t,
        filter: ?*const bson_t,
        opts: ?*const bson_t,
        read_prefs: ?*anyopaque,
    ) ?*mongoc_cursor_t;
    pub extern fn mongoc_collection_update_one(
        collection: ?*mongoc_collection_t,
        filter: ?*const bson_t,
        update: ?*const bson_t,
        opts: ?*const bson_t,
        reply: ?*bson_t,
        err: ?*bson_error_t,
    ) bool;
    pub extern fn mongoc_collection_delete_one(
        collection: ?*mongoc_collection_t,
        filter: ?*const bson_t,
        opts: ?*const bson_t,
        reply: ?*bson_t,
        err: ?*bson_error_t,
    ) bool;
    pub extern fn mongoc_collection_count_documents(
        collection: ?*mongoc_collection_t,
        filter: ?*const bson_t,
        opts: ?*const bson_t,
        read_prefs: ?*anyopaque,
        err: ?*bson_error_t,
    ) i64;
    pub extern fn mongoc_cursor_next(
        cursor: ?*mongoc_cursor_t,
        bson: ?*?*const bson_t,
    ) bool;
    pub extern fn mongoc_cursor_destroy(cursor: ?*mongoc_cursor_t) void;
    pub extern fn mongoc_cursor_error(
        cursor: ?*mongoc_cursor_t,
        err: ?*bson_error_t,
    ) bool;
    pub extern fn bson_new() ?*bson_t;
    pub extern fn bson_destroy(bson: ?*bson_t) void;
    pub extern fn bson_append_utf8(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
        value: [*]const u8,
        value_len: c_int,
    ) bool;
    pub extern fn bson_append_int64(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
        value: i64,
    ) bool;
    pub extern fn bson_append_double(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
        value: f64,
    ) bool;
    pub extern fn bson_append_bool(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
        value: bool,
    ) bool;
    pub extern fn bson_append_oid(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
        value: ?*const bson_oid_t,
    ) bool;
    pub extern fn bson_append_null(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
    ) bool;
    pub extern fn bson_append_document(
        bson: ?*bson_t,
        key: [*:0]const u8,
        key_len: c_int,
        value: ?*const bson_t,
    ) bool;
    pub extern fn bson_iter_init(
        iter: ?*bson_iter_t,
        bson: ?*const bson_t,
    ) bool;
    pub extern fn bson_iter_next(iter: ?*bson_iter_t) bool;
    pub extern fn bson_iter_key(iter: ?*const bson_iter_t) [*:0]const u8;
    pub extern fn bson_iter_type(iter: ?*const bson_iter_t) c_int;
    pub extern fn bson_iter_utf8(
        iter: ?*const bson_iter_t,
        length: ?*u32,
    ) [*]const u8;
    pub extern fn bson_iter_int64(iter: ?*const bson_iter_t) i64;
    pub extern fn bson_iter_int32(iter: ?*const bson_iter_t) i32;
    pub extern fn bson_iter_double(iter: ?*const bson_iter_t) f64;
    pub extern fn bson_iter_bool(iter: ?*const bson_iter_t) bool;
    pub extern fn bson_iter_oid(iter: ?*const bson_iter_t) ?*const bson_oid_t;
    pub extern fn bson_oid_init_sequence(oid: ?*bson_oid_t) void;
    pub extern fn bson_oid_to_string(
        oid: ?*const bson_oid_t,
        str: [*:0]u8,
    ) void;
} else struct {};

pub const MongoStore = if (build_config.has_mongodb) struct {
    const Self = @This();
    const log = std.log.scoped(.db_mongodb);

    client: ?*c.mongoc_client_t,
    gpa: std.mem.Allocator,
    db_name: [:0]const u8,

    var mongoc_initialized: bool = false;

    fn ensureInit() void {
        if (!mongoc_initialized) {
            c.mongoc_init();
            mongoc_initialized = true;
        }
    }

    fn documentToBson(doc: *const Document, gpa: std.mem.Allocator) (error{AllocatorFailed} || std.mem.Allocator.Error)!*c.bson_t {
        const bson = c.bson_new() orelse return error.AllocatorFailed;
        errdefer c.bson_destroy(bson);

        var it = doc.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const key_z = try gpa.dupeSentinel(u8, key, 0);
            defer gpa.free(key_z);

            switch (val) {
                .string => |s| {
                    if (!c.bson_append_utf8(bson, key_z.ptr, @intCast(key_z.len), s.ptr, @intCast(s.len))) return error.AllocatorFailed;
                },
                .int => |v| {
                    if (!c.bson_append_int64(bson, key_z.ptr, @intCast(key_z.len), v)) return error.AllocatorFailed;
                },
                .float => |v| {
                    if (!c.bson_append_double(bson, key_z.ptr, @intCast(key_z.len), v)) return error.AllocatorFailed;
                },
                .bool => |v| {
                    if (!c.bson_append_bool(bson, key_z.ptr, @intCast(key_z.len), v)) return error.AllocatorFailed;
                },
                .oid => |o| {
                    var c_oid = c.bson_oid_t{ .bytes = o };
                    if (!c.bson_append_oid(bson, key_z.ptr, @intCast(key_z.len), &c_oid)) return error.AllocatorFailed;
                },
                .null => {
                    if (!c.bson_append_null(bson, key_z.ptr, @intCast(key_z.len))) return error.AllocatorFailed;
                },
                .doc => |nested| {
                    const nested_bson = try documentToBson(nested, gpa);
                    defer c.bson_destroy(nested_bson);
                    if (!c.bson_append_document(bson, key_z.ptr, @intCast(key_z.len), nested_bson)) return error.AllocatorFailed;
                },
                .arr => |arr| {
                    const arr_bson = try arrayToBson(arr, gpa);
                    defer c.bson_destroy(arr_bson);
                    if (!c.bson_append_document(bson, key_z.ptr, @intCast(key_z.len), arr_bson)) return error.AllocatorFailed;
                },
            }
        }

        return bson;
    }

    fn arrayToBson(arr: *const std.ArrayList(iface.BsonValue), gpa: std.mem.Allocator) (error{AllocatorFailed} || std.mem.Allocator.Error)!*c.bson_t {
        const bson = c.bson_new() orelse return error.AllocatorFailed;
        errdefer c.bson_destroy(bson);

        for (arr.items, 0..) |item, i| {
            var idx_buf: [32]u8 = undefined;
            const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch "0";
            const idx_z = try gpa.dupeSentinel(u8, idx_str, 0);
            defer gpa.free(idx_z);

            switch (item) {
                .string => |s| {
                    if (!c.bson_append_utf8(bson, idx_z.ptr, @intCast(idx_z.len), s.ptr, @intCast(s.len))) return error.AllocatorFailed;
                },
                .int => |v| {
                    if (!c.bson_append_int64(bson, idx_z.ptr, @intCast(idx_z.len), v)) return error.AllocatorFailed;
                },
                .float => |v| {
                    if (!c.bson_append_double(bson, idx_z.ptr, @intCast(idx_z.len), v)) return error.AllocatorFailed;
                },
                .bool => |v| {
                    if (!c.bson_append_bool(bson, idx_z.ptr, @intCast(idx_z.len), v)) return error.AllocatorFailed;
                },
                .oid => |o| {
                    var c_oid = c.bson_oid_t{ .bytes = o };
                    if (!c.bson_append_oid(bson, idx_z.ptr, @intCast(idx_z.len), &c_oid)) return error.AllocatorFailed;
                },
                .null => {
                    if (!c.bson_append_null(bson, idx_z.ptr, @intCast(idx_z.len))) return error.AllocatorFailed;
                },
                .doc => |nested| {
                    const nested_bson = try documentToBson(nested, gpa);
                    defer c.bson_destroy(nested_bson);
                    if (!c.bson_append_document(bson, idx_z.ptr, @intCast(idx_z.len), nested_bson)) return error.AllocatorFailed;
                },
                .arr => |sub_arr| {
                    const sub_bson = try arrayToBson(sub_arr, gpa);
                    defer c.bson_destroy(sub_bson);
                    if (!c.bson_append_document(bson, idx_z.ptr, @intCast(idx_z.len), sub_bson)) return error.AllocatorFailed;
                },
            }
        }

        return bson;
    }

    fn bsonToDocument(bson: *const c.bson_t, gpa: std.mem.Allocator) (DocumentError || std.mem.Allocator.Error)!Document {
        var doc = Document.init(gpa);
        errdefer {
            var d = doc;
            d.deinit();
        }

        var iter: c.bson_iter_t = undefined;
        if (!c.bson_iter_init(&iter, bson)) return error.FindFailed;

        while (c.bson_iter_next(&iter)) {
            const key = std.mem.sliceTo(c.bson_iter_key(&iter), 0);
            const bson_type = c.bson_iter_type(&iter);

            const value = switch (bson_type) {
                c.BSON_TYPE_UTF8 => blk: {
                    var len: u32 = 0;
                    const ptr = c.bson_iter_utf8(&iter, &len);
                    break :blk iface.BsonValue{ .string = ptr[0..len] };
                },
                c.BSON_TYPE_INT64 => iface.BsonValue{ .int = c.bson_iter_int64(&iter) },
                c.BSON_TYPE_INT32 => iface.BsonValue{ .int = c.bson_iter_int32(&iter) },
                c.BSON_TYPE_DOUBLE => iface.BsonValue{ .float = c.bson_iter_double(&iter) },
                c.BSON_TYPE_BOOL => iface.BsonValue{ .bool = c.bson_iter_bool(&iter) },
                c.BSON_TYPE_OID => blk: {
                    const c_oid = c.bson_iter_oid(&iter) orelse break :blk iface.BsonValue{ .null = {} };
                    break :blk iface.BsonValue{ .oid = c_oid.bytes };
                },
                c.BSON_TYPE_NULL => iface.BsonValue{ .null = {} },
                c.BSON_TYPE_DOCUMENT => blk: {
                    const nested_doc = try bsonToDocument(bson, gpa);
                    const heap_doc = try gpa.create(Document);
                    heap_doc.* = nested_doc;
                    break :blk iface.BsonValue{ .doc = heap_doc };
                },
                else => iface.BsonValue{ .null = {} },
            };

            const owned_key = try gpa.dupe(u8, key);
            errdefer gpa.free(owned_key);

            switch (value) {
                .string => |s| {
                    const owned_val = try gpa.dupe(u8, s);
                    try doc.put(owned_key, .{ .string = owned_val });
                },
                .int => |v| try doc.put(owned_key, .{ .int = v }),
                .float => |v| try doc.put(owned_key, .{ .float = v }),
                .bool => |v| try doc.put(owned_key, .{ .bool = v }),
                .oid => |v| try doc.put(owned_key, .{ .oid = v }),
                .null => try doc.put(owned_key, .{ .null = {} }),
                .doc => |v| try doc.put(owned_key, .{ .doc = v }),
                .arr => |v| try doc.put(owned_key, .{ .arr = v }),
            }
        }

        return doc;
    }

    pub fn open(gpa: std.mem.Allocator, uri: []const u8, default_db: []const u8) (DocumentError || std.mem.Allocator.Error)!MongoStore {
        ensureInit();
        const uri_z = try gpa.dupeSentinel(u8, uri, 0);
        defer gpa.free(uri_z);

        const client = c.mongoc_client_new(uri_z.ptr) orelse {
            log.err("mongoc_client_new failed for URI: {s}", .{uri});
            return error.OpenFailed;
        };

        const db_z = try gpa.dupeSentinel(u8, default_db, 0);
        errdefer gpa.free(db_z);

        log.debug("opened MongoDB connection: db={s}", .{default_db});
        return .{ .client = client, .gpa = gpa, .db_name = db_z };
    }

    pub fn collection(self: *MongoStore, name: []const u8) iface.Collection {
        const name_z = self.gpa.dupeSentinel(u8, name, 0) catch @panic("OOM");
        const raw = c.mongoc_client_get_collection(self.client, self.db_name.ptr, name_z.ptr);
        self.gpa.free(name_z);
        const col_handle = raw orelse @panic("mongoc_client_get_collection returned null");
        const mongo_col = self.gpa.create(MongoCollection) catch @panic("OOM");
        mongo_col.* = MongoCollection{
            .handle = col_handle,
            .gpa = self.gpa,
        };
        return .{
            .ptr = @ptrCast(mongo_col),
            .vtable = &.{
                .insertOne = struct {
                    fn f(ptr: *anyopaque, gpa: std.mem.Allocator, doc: *const Document) DocumentError!ObjectId {
                        var col: *MongoCollection = @ptrCast(@alignCast(ptr));
                        return col.insertOne(gpa, doc);
                    }
                }.f,
                .findOne = struct {
                    fn f(ptr: *anyopaque, gpa: std.mem.Allocator, filter: *const Filter) DocumentError!?Document {
                        var col: *MongoCollection = @ptrCast(@alignCast(ptr));
                        return col.findOne(gpa, filter);
                    }
                }.f,
                .updateOne = struct {
                    fn f(ptr: *anyopaque, filter: *const Filter, update: *const Document) DocumentError!void {
                        var col: *MongoCollection = @ptrCast(@alignCast(ptr));
                        try col.updateOne(filter, update);
                    }
                }.f,
                .deleteOne = struct {
                    fn f(ptr: *anyopaque, filter: *const Filter) DocumentError!void {
                        var col: *MongoCollection = @ptrCast(@alignCast(ptr));
                        try col.deleteOne(filter);
                    }
                }.f,
                .countDocuments = struct {
                    fn f(ptr: *anyopaque, filter: *const Filter) DocumentError!u64 {
                        var col: *MongoCollection = @ptrCast(@alignCast(ptr));
                        return try col.countDocuments(filter);
                    }
                }.f,
                .close = struct {
                    fn f(ptr: *anyopaque) void {
                        var col: *MongoCollection = @ptrCast(@alignCast(ptr));
                        col.close();
                    }
                }.f,
            },
        };
    }

    pub fn close(self: *MongoStore) void {
        if (self.client) |c_ptr| {
            c.mongoc_client_destroy(c_ptr);
            self.client = null;
        }
        self.gpa.free(self.db_name);
        log.debug("closed MongoDB connection", .{});
    }

    pub fn asDocumentStore(self: *MongoStore) iface.DocumentStore {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .collection = struct {
                    fn f(ptr: *anyopaque, name: []const u8) iface.Collection {
                        var store: *MongoStore = @ptrCast(@alignCast(ptr));
                        return store.collection(name);
                    }
                }.f,
                .close = struct {
                    fn f(ptr: *anyopaque) void {
                        var store: *MongoStore = @ptrCast(@alignCast(ptr));
                        store.close();
                    }
                }.f,
            },
        };
    }

    const MongoCollection = struct {
        handle: *c.mongoc_collection_t,
        gpa: std.mem.Allocator,

        fn insertOne(self: *@This(), gpa: std.mem.Allocator, doc: *const Document) DocumentError!ObjectId {
            const bson_doc = documentToBson(doc, gpa) catch return error.AllocatorFailed;
            defer c.bson_destroy(bson_doc);

            const reply = c.bson_new() orelse return error.AllocatorFailed;
            defer c.bson_destroy(reply);

            var error_obj: c.bson_error_t = undefined;
            if (!c.mongoc_collection_insert_one(self.handle, bson_doc, null, reply, &error_obj)) {
                log.err("insert_one failed: domain={d} code={d} msg={s}", .{
                    error_obj.domain, error_obj.code, error_obj.message[0..],
                });
                return error.InsertFailed;
            }

            return extractOidFromReply(reply, gpa);
        }

        fn findOne(self: *@This(), gpa: std.mem.Allocator, filter: *const Filter) DocumentError!?Document {
            const bson_filter = documentToBson(filter, gpa) catch return error.AllocatorFailed;
            defer c.bson_destroy(bson_filter);

            const cursor = c.mongoc_collection_find_with_opts(self.handle, bson_filter, null, null) orelse return error.FindFailed;
            defer c.mongoc_cursor_destroy(cursor);

            var raw_bson: ?*const c.bson_t = null;
            if (!c.mongoc_cursor_next(cursor, &raw_bson)) {
                var error_obj: c.bson_error_t = undefined;
                if (c.mongoc_cursor_error(cursor, &error_obj)) {
                    log.err("cursor error: domain={d} code={d} msg={s}", .{
                        error_obj.domain, error_obj.code, error_obj.message[0..],
                    });
                    return error.FindFailed;
                }
                return null;
            }

            return bsonToDocument(raw_bson.?, gpa) catch return error.AllocatorFailed;
        }

        fn updateOne(self: *@This(), filter: *const Filter, update: *const Document) DocumentError!void {
            const gpa = self.gpa;
            const bson_filter = documentToBson(filter, gpa) catch return error.AllocatorFailed;
            defer c.bson_destroy(bson_filter);

            const bson_update = documentToBson(update, gpa) catch return error.AllocatorFailed;
            defer c.bson_destroy(bson_update);

            var error_obj: c.bson_error_t = undefined;
            if (!c.mongoc_collection_update_one(self.handle, bson_filter, bson_update, null, null, &error_obj)) {
                log.err("update_one failed: domain={d} code={d} msg={s}", .{
                    error_obj.domain, error_obj.code, error_obj.message[0..],
                });
                return error.UpdateFailed;
            }
        }

        fn deleteOne(self: *@This(), filter: *const Filter) DocumentError!void {
            const gpa = self.gpa;
            const bson_filter = documentToBson(filter, gpa) catch return error.AllocatorFailed;
            defer c.bson_destroy(bson_filter);

            var error_obj: c.bson_error_t = undefined;
            if (!c.mongoc_collection_delete_one(self.handle, bson_filter, null, null, &error_obj)) {
                log.err("delete_one failed: domain={d} code={d} msg={s}", .{
                    error_obj.domain, error_obj.code, error_obj.message[0..],
                });
                return error.DeleteFailed;
            }
        }

        fn countDocuments(self: *@This(), filter: *const Filter) DocumentError!u64 {
            const gpa = self.gpa;
            const bson_filter = documentToBson(filter, gpa) catch return error.AllocatorFailed;
            defer c.bson_destroy(bson_filter);

            var error_obj: c.bson_error_t = undefined;
            const count = c.mongoc_collection_count_documents(self.handle, bson_filter, null, null, &error_obj);
            if (count < 0) {
                log.err("count_documents failed: domain={d} code={d} msg={s}", .{
                    error_obj.domain, error_obj.code, error_obj.message[0..],
                });
                return error.FindFailed;
            }
            return @intCast(count);
        }

        fn close(self: *@This()) void {
            c.mongoc_collection_destroy(self.handle);
        }
    };

    fn extractOidFromReply(reply: *const c.bson_t, gpa: std.mem.Allocator) DocumentError!ObjectId {
        var iter: c.bson_iter_t = undefined;
        if (!c.bson_iter_init(&iter, reply)) return error.InsertFailed;

        while (c.bson_iter_next(&iter)) {
            const key = std.mem.sliceTo(c.bson_iter_key(&iter), 0);
            if (std.mem.eql(u8, key, "insertedId")) {
                const bson_type = c.bson_iter_type(&iter);
                if (bson_type == c.BSON_TYPE_OID) {
                    const c_oid = c.bson_iter_oid(&iter) orelse return error.InsertFailed;
                    return c_oid.bytes;
                }
                if (bson_type == c.BSON_TYPE_DOCUMENT) {
                    return extractOidFromReply(reply, gpa);
                }
            }
        }

        return generateOid();
    }

    fn generateOid() ObjectId {
        var c_oid: c.bson_oid_t = undefined;
        c.bson_oid_init_sequence(&c_oid);
        return c_oid.bytes;
    }
} else void;
