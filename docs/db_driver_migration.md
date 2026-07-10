# Multi-Database Driver Migration

> **Phase 13** of the zypher framework introduces a driver abstraction layer so that the ORM, schema generator, migration runner, and query builder work with any relational database (SQLite, PostgreSQL, MySQL/MariaDB) and optionally with non-relational stores (MongoDB, Redis). After this phase, no source file outside `src/orm/driver/` touches a database-specific C API directly.

## Invariant

**The database driver is always caller-supplied.** The `RelationalDb`, `DocumentStore`, and `KVStore` vtable interfaces follow the `std.Io` / `std.mem.Allocator` convention: a vtable pointer held by value, no heap allocation for the interface itself. Users select the driver at app-init time via `App.useDatabase()`.

## Functions That Gain or Change a Driver Parameter

### ORM Core

| Module | Function | Change |
|--------|----------|--------|
| `query.zig` | `create` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `getById` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `all` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `updateById` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `deleteById` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `order` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `count` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `filter` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `filterLimitOffset` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `filterOrderLimitOffset` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `first` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `save` | `db: *sqlite.Db` → `db: RelationalDb` |
| `query.zig` | `QuerySet` | `db: *sqlite.Db` → `db: RelationalDb` |
| `migration.zig` | `MigrationRunner.init` | `db: *sqlite.Db` → `db: RelationalDb` |
| `migration.zig` | `ensureHistoryTable` | Uses `db.dialect()` for DDL |
| `schema.zig` | `createTableSql` | New: `comptime dialect: Dialect` parameter |
| `schema.zig` | `insertSql` | New: `comptime dialect: Dialect` parameter |
| `schema.zig` | `selectByIdSql` | New: `comptime dialect: Dialect` parameter |
| `schema.zig` | `updateByIdSql` | New: `comptime dialect: Dialect` parameter |
| `schema.zig` | `migrationHistoryTableSql` | New: `comptime dialect: Dialect` parameter |

### App / Admin / CLI

| Module | Function | Change |
|--------|----------|--------|
| `app.zig` | `db` field | `?*sqlite.Db` → `?OpenDb` |
| `app.zig` | `useDatabase` | New method accepting `DatabaseConfig` |
| `app.zig` | `db()` | Returns `RelationalDb` instead of `*sqlite.Db` |
| `app.zig` | `database` | Removed — replaced by `useDatabase` |
| `admin/registry.zig` | `setDb` | `*sqlite.Db` → `RelationalDb` |
| `cli/runner.zig` | `cmdMigrate` | `--driver` flag; uses `DatabaseConfig` |
| `cli/runner.zig` | `cmdCreatesuperuser` | `RelationalDb` |

## Hardcoded SQL Type / Placeholder Changes

| Current (SQLite-only) | After Migration |
|-----------------------|-----------------|
| `INTEGER PRIMARY KEY AUTOINCREMENT` | `dialect.pk_type` |
| `REAL` | `dialect.float_type` |
| `INTEGER` (for bool) | `dialect.bool_type` |
| `strftime('%s','now')` | `dialect.timestamp_now` |
| `?` placeholders | `dialect.placeholder(i, &buf)` → `?` (SQLite/MySQL) or `$N` (PostgreSQL) |

## Driver Structure

```
src/orm/
├── driver/
│   ├── interface.zig    # RelationalDb, AnyStmt, Dialect vtable types
│   ├── sqlite.zig       # SQLite driver (moved from src/orm/sqlite.zig)
│   ├── postgres.zig     # PostgreSQL driver (requires -Ddb_postgres=true)
│   └── mysql.zig        # MySQL driver (requires -Ddb_mysql=true)
├── document/
│   ├── interface.zig    # DocumentStore, Collection vtable types
│   └── mongodb.zig      # MongoDB driver (requires -Ddb_mongodb=true)
├── kv/
│   ├── interface.zig    # KVStore vtable types
│   └── redis.zig        # Redis driver (requires -Ddb_redis=true)
├── config.zig           # DatabaseConfig union + openDatabase()
├── schema.zig           # Dialect-parameterised SQL generation
├── query.zig            # RelationalDb-based query builder
├── migration.zig        # RelationalDb-based migration runner
└── sqlite.zig           # Backward-compat re-export shim
```

## Example: Using zypher with PostgreSQL

```zig
const std = @import("std");
const zypher = @import("zypher");

pub fn main(init: std.process.Init) !void {
    var app = zypher.core.App.init(init.gpa, .{ .port = 8080 });
    defer app.deinit();

    try app.useDatabase(init.gpa, init.io, .{
        .postgres = .{ .connstr = "postgresql://user:pass@localhost:5432/mydb" },
    });

    // app.db() returns RelationalDb — works with query.zig and migration.zig
    const db = try app.db();
    _ = db; // use with QuerySet, create, filter, etc.

    try app.listenAndServe(init.io);
}
```

## Build Flags

| Flag | Default | Links | Driver |
|------|---------|-------|--------|
| (none) | always | vendored sqlite3 | SQLite |
| `-Ddb_postgres=true` | false | system libpq | PostgreSQL |
| `-Ddb_mysql=true` | false | system libmysqlclient | MySQL/MariaDB |
| `-Ddb_mongodb=true` | false | system libmongoc | MongoDB |
| `-Ddb_redis=true` | false | system libhiredis | Redis |

## CI Guard Exclusions

The `zig build test-io-clean` step excludes these paths (they legitimately use `std.Io` for TCP, not banned `std.net`):

- `src/orm/driver/` — PostgreSQL, MySQL, Redis drivers use `std.Io` for network I/O
- `src/orm/document/` — MongoDB driver uses `std.Io` for network I/O
- `src/orm/kv/` — Redis driver uses `std.Io` for network I/O
