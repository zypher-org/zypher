const std = @import("std");
const build_config = @import("build_config");
const driver_iface = @import("driver/interface.zig");
const doc_iface = @import("document/interface.zig");
const kv_iface = @import("kv/interface.zig");

pub const RelationalDb = driver_iface.RelationalDb;
pub const DocumentStore = doc_iface.DocumentStore;
pub const KVStore = kv_iface.KVStore;

/// Configuration types for each supported database.
pub const SqliteConfig = struct { path: [:0]const u8 = "db.sqlite" };
pub const PostgresConfig = struct { connstr: [:0]const u8 };
pub const MysqlConfig = struct {
    host: [:0]const u8 = "127.0.0.1",
    user: [:0]const u8 = "root",
    pass: [:0]const u8 = "",
    db: [:0]const u8,
    port: u16 = 3306,
};
pub const MongoConfig = struct { uri: [:0]const u8, default_db: [:0]const u8 };
pub const RedisConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 6379,
    db: u8 = 0,
    password: ?[]const u8 = null,
};

/// Tagged union: choose one at app-init time.
pub const DatabaseConfig = union(enum) {
    sqlite: SqliteConfig,
    postgres: PostgresConfig,
    mysql: MysqlConfig,
    mongo: MongoConfig,
    redis: RedisConfig,
};

pub const ConfigError = error{
    NoDatabaseConfigured,
    WrongStoreType,
    DriverNotEnabled,
    OpenFailed,
    AllocatorFailed,
};

/// Holds a heap-allocated driver struct with type-erased cleanup.
/// The concrete vtable wrapper (RelationalDb / DocumentStore / KVStore)
/// is returned alongside this in OpenResult.
pub const OpenDb = struct {
    ptr: *anyopaque,
    deinitFn: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator) void,
    kind: Kind,

    pub const Kind = enum { relational, document, kv };

    pub fn close(self: *OpenDb, gpa: std.mem.Allocator) void {
        self.deinitFn(self.ptr, gpa);
    }
};

/// Return type from openDatabase. Contains the owned cleanup handle
/// plus the typed vtable wrapper that corresponds to the config variant.
pub const OpenResult = struct {
    open_db: OpenDb,
    relational: ?RelationalDb = null,
    document: ?DocumentStore = null,
    kv: ?KVStore = null,
};

/// Open a database from a config union. The OpenResult owns the
/// underlying driver — call open_db.close() to release resources.
pub fn openDatabase(gpa: std.mem.Allocator, cfg: DatabaseConfig) (ConfigError || std.mem.Allocator.Error)!OpenResult {
    return switch (cfg) {
        .sqlite => |c| openSqlite(gpa, c),
        .postgres => |c| openPostgres(gpa, c),
        .mysql => |c| openMysql(gpa, c),
        .mongo => |c| openMongo(gpa, c),
        .redis => |c| openRedis(gpa, c),
    };
}

fn openSqlite(gpa: std.mem.Allocator, cfg: SqliteConfig) (ConfigError || std.mem.Allocator.Error)!OpenResult {
    const Driver = @import("driver/sqlite.zig");
    const db = try gpa.create(Driver.SqliteDb);
    db.* = Driver.SqliteDb.open(gpa, cfg.path) catch |e| {
        gpa.destroy(db);
        return switch (e) {
            error.OpenFailed => error.OpenFailed,
            error.AllocatorFailed => error.AllocatorFailed,
            error.PrepareFailed => error.OpenFailed,
            error.ExecFailed => error.OpenFailed,
            error.StepFailed => error.OpenFailed,
            error.BindFailed => error.OpenFailed,
            error.ColumnFailed => error.OpenFailed,
            error.ConstraintViolation => error.OpenFailed,
            error.UnexpectedResult => error.OpenFailed,
        };
    };
    const relational = db.asRelationalDb();
    return OpenResult{
        .open_db = .{
            .ptr = @ptrCast(db),
            .deinitFn = struct {
                fn f(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const d: *Driver.SqliteDb = @ptrCast(@alignCast(ptr));
                    d.close();
                    alloc.destroy(d);
                }
            }.f,
            .kind = .relational,
        },
        .relational = relational,
    };
}

fn openPostgres(gpa: std.mem.Allocator, cfg: PostgresConfig) (ConfigError || std.mem.Allocator.Error)!OpenResult {
    if (!build_config.has_postgres) return error.DriverNotEnabled;
    const Driver = @import("driver/postgres.zig");
    const db = try gpa.create(Driver.PostgresDb);
    db.* = Driver.PostgresDb.open(gpa, cfg.connstr) catch |e| {
        gpa.destroy(db);
        return switch (e) {
            error.OpenFailed => error.OpenFailed,
            error.AllocatorFailed => error.AllocatorFailed,
            error.PrepareFailed => error.OpenFailed,
            error.ExecFailed => error.OpenFailed,
            error.StepFailed => error.OpenFailed,
            error.BindFailed => error.OpenFailed,
            error.ColumnFailed => error.OpenFailed,
            error.ConstraintViolation => error.OpenFailed,
            error.UnexpectedResult => error.OpenFailed,
        };
    };
    const relational = db.asRelationalDb();
    return OpenResult{
        .open_db = .{
            .ptr = @ptrCast(db),
            .deinitFn = struct {
                fn f(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const d: *Driver.PostgresDb = @ptrCast(@alignCast(ptr));
                    d.close();
                    alloc.destroy(d);
                }
            }.f,
            .kind = .relational,
        },
        .relational = relational,
    };
}

fn openMysql(gpa: std.mem.Allocator, cfg: MysqlConfig) (ConfigError || std.mem.Allocator.Error)!OpenResult {
    if (!build_config.has_mysql) return error.DriverNotEnabled;
    const Driver = @import("driver/mysql.zig");
    const db = try gpa.create(Driver.MysqlDb);
    db.* = Driver.MysqlDb.open(gpa, .{
        .host = cfg.host,
        .user = cfg.user,
        .pass = cfg.pass,
        .db = cfg.db,
        .port = cfg.port,
    }) catch |e| {
        gpa.destroy(db);
        return switch (e) {
            error.OpenFailed => error.OpenFailed,
            error.AllocatorFailed => error.AllocatorFailed,
            error.PrepareFailed => error.OpenFailed,
            error.ExecFailed => error.OpenFailed,
            error.StepFailed => error.OpenFailed,
            error.BindFailed => error.OpenFailed,
            error.ColumnFailed => error.OpenFailed,
            error.ConstraintViolation => error.OpenFailed,
            error.UnexpectedResult => error.OpenFailed,
        };
    };
    const relational = db.asRelationalDb();
    return OpenResult{
        .open_db = .{
            .ptr = @ptrCast(db),
            .deinitFn = struct {
                fn f(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const d: *Driver.MysqlDb = @ptrCast(@alignCast(ptr));
                    d.close();
                    alloc.destroy(d);
                }
            }.f,
            .kind = .relational,
        },
        .relational = relational,
    };
}

fn openMongo(gpa: std.mem.Allocator, cfg: MongoConfig) (ConfigError || std.mem.Allocator.Error)!OpenResult {
    if (!build_config.has_mongodb) return error.DriverNotEnabled;
    const Driver = @import("document/mongodb.zig");
    const store = try gpa.create(Driver.MongoStore);
    store.* = Driver.MongoStore.open(gpa, cfg.uri, cfg.default_db) catch |e| {
        gpa.destroy(store);
        return switch (e) {
            error.OpenFailed => error.OpenFailed,
            error.AllocatorFailed => error.AllocatorFailed,
            error.InsertFailed => error.OpenFailed,
            error.FindFailed => error.OpenFailed,
            error.UpdateFailed => error.OpenFailed,
            error.DeleteFailed => error.OpenFailed,
            error.CursorFailed => error.OpenFailed,
            error.OutOfMemory => error.OutOfMemory,
        };
    };
    const document = store.asDocumentStore();
    return OpenResult{
        .open_db = .{
            .ptr = @ptrCast(store),
            .deinitFn = struct {
                fn f(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const d: *Driver.MongoStore = @ptrCast(@alignCast(ptr));
                    d.close();
                    alloc.destroy(d);
                }
            }.f,
            .kind = .document,
        },
        .document = document,
    };
}

fn openRedis(gpa: std.mem.Allocator, cfg: RedisConfig) (ConfigError || std.mem.Allocator.Error)!OpenResult {
    if (!build_config.has_redis) return error.DriverNotEnabled;
    const Driver = @import("kv/redis.zig");
    const store = try gpa.create(Driver.RedisStore);
    store.* = Driver.RedisStore.open(gpa, .{
        .host = cfg.host,
        .port = cfg.port,
        .db = cfg.db,
        .password = cfg.password,
    }) catch |e| {
        gpa.destroy(store);
        return switch (e) {
            error.OpenFailed => error.OpenFailed,
            error.AllocatorFailed => error.AllocatorFailed,
            error.GetFailed => error.OpenFailed,
            error.SetFailed => error.OpenFailed,
            error.DelFailed => error.OpenFailed,
            error.ExpireFailed => error.OpenFailed,
            error.HashFailed => error.OpenFailed,
            error.ListFailed => error.OpenFailed,
        };
    };
    const kv = store.asKVStore();
    return OpenResult{
        .open_db = .{
            .ptr = @ptrCast(store),
            .deinitFn = struct {
                fn f(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const d: *Driver.RedisStore = @ptrCast(@alignCast(ptr));
                    d.close();
                    alloc.destroy(d);
                }
            }.f,
            .kind = .kv,
        },
        .kv = kv,
    };
}
