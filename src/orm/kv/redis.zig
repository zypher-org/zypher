const std = @import("std");
const build_config = @import("build_config");
const iface = @import("interface.zig");

pub const enabled = build_config.has_redis;

pub const KVError = iface.KVError;
pub const KVStore = iface.KVStore;

pub const RedisConfig = if (build_config.has_redis) struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 6379,
    db: u8 = 0,
    password: ?[]const u8 = null,
} else void;

pub const c = if (build_config.has_redis) struct {
    pub const redisContext = extern struct {
        err: c_int,
        errstr: [256]u8,
        fd: c_int,
        flags: c_int,
        obuf: ?*u8,
        reader: ?*anyopaque,
        privdata: ?*anyopaque,
    };

    pub const redisReply = extern struct {
        type: c_int,
        integer: i64,
        len: usize,
        str: ?[*:0]u8,
        elements: usize,
        element: ?[*]?*redisReply,
    };

    pub const REDIS_REPLY_STRING: c_int = 1;
    pub const REDIS_REPLY_ARRAY: c_int = 2;
    pub const REDIS_REPLY_INTEGER: c_int = 3;
    pub const REDIS_REPLY_NIL: c_int = 4;
    pub const REDIS_REPLY_STATUS: c_int = 5;
    pub const REDIS_REPLY_ERROR: c_int = 6;

    pub extern fn redisConnect(ip: [*:0]const u8, port: c_int) ?*redisContext;
    pub extern fn redisFree(c: ?*redisContext) void;
    pub extern fn redisCommand(c: ?*redisContext, format: [*:0]const u8, ...) ?*redisReply;
    pub extern fn freeReplyObject(reply: ?*redisReply) void;
} else struct {};

pub const RedisStore = if (build_config.has_redis) struct {
    const Self = @This();
    const log = std.log.scoped(.db_redis);

    ctx: *c.redisContext,
    gpa: std.mem.Allocator,

    pub fn open(gpa: std.mem.Allocator, config: RedisConfig) KVError!RedisStore {
        const host_z = try gpa.dupeZ(u8, config.host);
        defer gpa.free(host_z);

        const ctx = c.redisConnect(host_z.ptr, @intCast(config.port)) orelse {
            log.err("redisConnect returned null", .{});
            return error.OpenFailed;
        };

        if (ctx.err != 0) {
            const msg = std.mem.sliceTo(&ctx.errstr, 0);
            log.err("redisConnect failed: {s}", .{msg});
            c.redisFree(ctx);
            return error.OpenFailed;
        }

        log.debug("connected to Redis {s}:{d}", .{ config.host, config.port });

        if (config.password) |pass| {
            const pz = try gpa.dupeZ(u8, pass);
            defer gpa.free(pz);
            const auth_reply = c.redisCommand(ctx, "AUTH %s", pz.ptr) orelse {
                c.redisFree(ctx);
                return error.OpenFailed;
            };
            defer c.freeReplyObject(auth_reply);
            if (auth_reply.type == c.REDIS_REPLY_ERROR) {
                log.err("AUTH failed", .{});
                c.redisFree(ctx);
                return error.OpenFailed;
            }
        }

        if (config.db > 0) {
            const select_reply = c.redisCommand(ctx, "SELECT %d", @as(c_int, config.db)) orelse {
                c.redisFree(ctx);
                return error.OpenFailed;
            };
            defer c.freeReplyObject(select_reply);
            if (select_reply.type == c.REDIS_REPLY_ERROR) {
                log.err("SELECT failed for db {d}", .{config.db});
                c.redisFree(ctx);
                return error.OpenFailed;
            }
        }

        return .{ .ctx = ctx, .gpa = gpa };
    }

    fn checkReply(reply: ?*c.redisReply) KVError!void {
        const r = reply orelse return error.SetFailed;
        if (r.type == c.REDIS_REPLY_ERROR) {
            const msg: []const u8 = if (r.str) |s| std.mem.sliceTo(s, 0) else "unknown";
            log.err("Redis command error: {s}", .{msg});
            return error.SetFailed;
        }
    }

    fn errorForOp(op: []const u8) KVError {
        log.err("{s} operation failed", .{op});
        return error.SetFailed;
    }

    pub fn set(self: *RedisStore, key: []const u8, value: []const u8) KVError!void {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const vz = try self.gpa.dupeZ(u8, value);
        defer self.gpa.free(vz);
        const reply = c.redisCommand(self.ctx, "SET %s %s", kz.ptr, vz.ptr) orelse return errorForOp("SET");
        defer c.freeReplyObject(reply);
        try checkReply(reply);
    }

    pub fn get(self: *RedisStore, gpa: std.mem.Allocator, key: []const u8) KVError!?[]const u8 {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const reply = c.redisCommand(self.ctx, "GET %s", kz.ptr) orelse return errorForOp("GET");
        defer c.freeReplyObject(reply);

        if (reply.type == c.REDIS_REPLY_NIL) return null;
        if (reply.type != c.REDIS_REPLY_STRING) return error.GetFailed;

        const s = reply.str orelse return error.GetFailed;
        return try gpa.dupe(u8, std.mem.sliceTo(s, 0));
    }

    pub fn del(self: *RedisStore, key: []const u8) KVError!void {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const reply = c.redisCommand(self.ctx, "DEL %s", kz.ptr) orelse return errorForOp("DEL");
        defer c.freeReplyObject(reply);
        try checkReply(reply);
    }

    pub fn exists(self: *RedisStore, key: []const u8) KVError!bool {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const reply = c.redisCommand(self.ctx, "EXISTS %s", kz.ptr) orelse return errorForOp("EXISTS");
        defer c.freeReplyObject(reply);
        if (reply.type == c.REDIS_REPLY_INTEGER) return reply.integer != 0;
        return error.ExpireFailed;
    }

    pub fn expire(self: *RedisStore, key: []const u8, seconds: i64) KVError!void {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const reply = c.redisCommand(self.ctx, "EXPIRE %s %d", kz.ptr, @as(c_int, @intCast(seconds))) orelse return errorForOp("EXPIRE");
        defer c.freeReplyObject(reply);
        try checkReply(reply);
    }

    pub fn hset(self: *RedisStore, key: []const u8, field: []const u8, value: []const u8) KVError!void {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const fz = try self.gpa.dupeZ(u8, field);
        defer self.gpa.free(fz);
        const vz = try self.gpa.dupeZ(u8, value);
        defer self.gpa.free(vz);
        const reply = c.redisCommand(self.ctx, "HSET %s %s %s", kz.ptr, fz.ptr, vz.ptr) orelse return errorForOp("HSET");
        defer c.freeReplyObject(reply);
        try checkReply(reply);
    }

    pub fn hget(self: *RedisStore, gpa: std.mem.Allocator, key: []const u8, field: []const u8) KVError!?[]const u8 {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const fz = try self.gpa.dupeZ(u8, field);
        defer self.gpa.free(fz);
        const reply = c.redisCommand(self.ctx, "HGET %s %s", kz.ptr, fz.ptr) orelse return errorForOp("HGET");
        defer c.freeReplyObject(reply);

        if (reply.type == c.REDIS_REPLY_NIL) return null;
        if (reply.type != c.REDIS_REPLY_STRING) return error.HashFailed;

        const s = reply.str orelse return error.HashFailed;
        return try gpa.dupe(u8, std.mem.sliceTo(s, 0));
    }

    pub fn lpush(self: *RedisStore, key: []const u8, value: []const u8) KVError!void {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const vz = try self.gpa.dupeZ(u8, value);
        defer self.gpa.free(vz);
        const reply = c.redisCommand(self.ctx, "LPUSH %s %s", kz.ptr, vz.ptr) orelse return errorForOp("LPUSH");
        defer c.freeReplyObject(reply);
        try checkReply(reply);
    }

    pub fn lrange(self: *RedisStore, gpa: std.mem.Allocator, key: []const u8, start: i64, stop: i64) KVError![]const []const u8 {
        const kz = try self.gpa.dupeZ(u8, key);
        defer self.gpa.free(kz);
        const reply = c.redisCommand(self.ctx, "LRANGE %s %d %d", kz.ptr, @as(c_int, @intCast(start)), @as(c_int, @intCast(stop))) orelse return errorForOp("LRANGE");
        defer c.freeReplyObject(reply);

        if (reply.type != c.REDIS_REPLY_ARRAY) return error.ListFailed;

        const elements = reply.elements;
        const items = reply.element orelse return error.ListFailed;

        var result = std.ArrayList([]const u8).init(gpa);
        errdefer result.deinit();

        for (0..elements) |i| {
            const elem = items[i] orelse continue;
            if (elem.type == c.REDIS_REPLY_STRING) {
                const s = elem.str orelse continue;
                const val = try gpa.dupe(u8, std.mem.sliceTo(s, 0));
                try result.append(val);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn close(self: *RedisStore) void {
        c.redisFree(self.ctx);
        log.debug("closed Redis connection", .{});
    }

    pub fn asKVStore(self: *RedisStore) KVStore {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .get = struct {
                    fn f(ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8) KVError!?[]const u8 {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        return try store.get(gpa, key);
                    }
                }.f,
                .set = struct {
                    fn f(ptr: *anyopaque, key: []const u8, value: []const u8) KVError!void {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        try store.set(key, value);
                    }
                }.f,
                .del = struct {
                    fn f(ptr: *anyopaque, key: []const u8) KVError!void {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        try store.del(key);
                    }
                }.f,
                .exists = struct {
                    fn f(ptr: *anyopaque, key: []const u8) KVError!bool {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        return try store.exists(key);
                    }
                }.f,
                .expire = struct {
                    fn f(ptr: *anyopaque, key: []const u8, seconds: i64) KVError!void {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        try store.expire(key, seconds);
                    }
                }.f,
                .hset = struct {
                    fn f(ptr: *anyopaque, key: []const u8, field: []const u8, value: []const u8) KVError!void {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        try store.hset(key, field, value);
                    }
                }.f,
                .hget = struct {
                    fn f(ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8, field: []const u8) KVError!?[]const u8 {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        return try store.hget(gpa, key, field);
                    }
                }.f,
                .lpush = struct {
                    fn f(ptr: *anyopaque, key: []const u8, value: []const u8) KVError!void {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        try store.lpush(key, value);
                    }
                }.f,
                .lrange = struct {
                    fn f(ptr: *anyopaque, gpa: std.mem.Allocator, key: []const u8, start: i64, stop: i64) KVError![]const []const u8 {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        return try store.lrange(gpa, key, start, stop);
                    }
                }.f,
                .close = struct {
                    fn f(ptr: *anyopaque) void {
                        var store: *RedisStore = @ptrCast(@alignCast(ptr));
                        store.close();
                    }
                }.f,
            },
        };
    }
} else void;
