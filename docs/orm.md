# ORM API

## Driver Interface (Multi-Database)

Zypher supports multiple database backends through a vtable-by-value interface. All relational operations use `RelationalDb` and `AnyStmt` regardless of the underlying driver.

### Interface Types (`orm.driver.interface` / `orm.*`)

- `RelationalDb` — vtable wrapper with `prepare`, `exec`, `close`, `lastInsertId`, `dialect`
- `AnyStmt` — vtable wrapper with `bind`, `step`, `column`, `columnType`, `reset`, `finalize`
- `Value` union: `int: i64`, `float: f64`, `text: []const u8`, `null: void`
- `ColumnType` enum: `integer`, `float`, `text`, `blob`, `null`
- `Dialect` — dialect metadata: `name`, `placeholder`, `pk_type`, `float_type`, `bool_type`, `text_type`, `timestamp_now`
- `DbError` error set: `OpenFailed`, `ExecFailed`, `PrepareFailed`, `StepFailed`, `BindFailed`, `ColumnFailed`, `ConstraintViolation`, `UnexpectedResult`

### SQLite Driver (`orm.driver.sqlite`)
- `SqliteDb.open(gpa, path) SqliteDb` — open a SQLite database
- `SqliteDb.asRelationalDb() RelationalDb` — wrap in vtable

### PostgreSQL Driver (`orm.driver.postgres`) [optional, `-Ddb_postgres=true`]
- `PostgresDb.open(gpa, connstr) PostgresDb` — open via libpq
- `PostgresDb.asRelationalDb() RelationalDb` — wrap in vtable

### MySQL Driver (`orm.driver.mysql`) [optional, `-Ddb_mysql=true`]
- `MysqlDb.open(gpa, config) MysqlDb` — open via libmysqlclient
- `MysqlDb.asRelationalDb() RelationalDb` — wrap in vtable

### Database Configuration API (`orm.config` / `orm.*`)
- `SqliteConfig`, `PostgresConfig`, `MysqlConfig`, `MongoConfig`, `RedisConfig`
- `DatabaseConfig` tagged union: `{ .sqlite = ... }`, `{ .postgres = ... }`, etc.
- `openDatabase(gpa, cfg) OpenResult` — open any backend from a config union
- `OpenResult` contains `open_db: OpenDb` (cleanup handle) + typed wrappers
- `DriverNotEnabled` error returned for disabled backends

Convenience re-exports at `orm.*`:

| Type | Path |
|------|------|
| `orm.RelationalDb` | `orm.driver.interface.RelationalDb` |
| `orm.DocumentStore` | `orm.document.interface.DocumentStore` |
| `orm.KVStore` | `orm.kv.interface.KVStore` |
| `orm.Value` | `orm.driver.interface.Value` |
| `orm.Dialect` | `orm.driver.interface.Dialect` |
| `orm.DatabaseConfig` | `orm.config.DatabaseConfig` |
| `orm.openDatabase` | `orm.config.openDatabase` |

## Schema
Comptime model and field definition.

### FieldKind
Enum: `integer`, `float`, `text`, `boolean`

### FieldOptions
- `primary: bool = false` — primary key field
- `required: bool = false` — NOT NULL
- `unique: bool = false` — UNIQUE constraint
- `foreign: ?[:0]const u8 = null` — FOREIGN KEY reference (e.g. `"users(id)"`)
- `default: ?DefaultValue = null` — DEFAULT value

### Field(name, kind, opts) FieldDef
Comptime field constructor. Returns a `FieldDef`:
- `name: [:0]const u8`
- `kind: FieldKind`
- `primary: bool`
- `required: bool`
- `unique: bool`
- `foreign: ?[:0]const u8`
- `default: ?DefaultValue`

### Model(table, Fields) type
Define a model type from a table name and a struct of `FieldDef` values.

Generated comptime constants:
- `model.table_name` — table name
- `model.fields_len` — number of fields
- `model.insert_field_count` — number of non-primary-key fields (for INSERT)
- `model.fieldAt(i) FieldDef` — get field definition by index
- `model.create_table_sql` — `CREATE TABLE IF NOT EXISTS ...` SQL
- `model.drop_table_sql` — `DROP TABLE IF EXISTS ...` SQL
- `model.insert_sql` — `INSERT INTO ... (cols) VALUES (?, ...)` SQL
- `model.select_all_sql` — `SELECT col1, col2, ... FROM table` SQL
- `model.select_by_id_sql` — `SELECT ... FROM table WHERE id = ?` SQL
- `model.update_by_id_sql` — `UPDATE table SET col1 = ?, ... WHERE id = ?` SQL
- `model.delete_by_id_sql` — `DELETE FROM table WHERE id = ?` SQL

## Query
Runtime query execution using comptime-generated SQL.

### RowType(M) type
Returns a tuple type matching the model's fields: `i64` for integer, `f64` for float, `[]const u8` for text, `bool` for boolean.

### freeRow(M, gpa, row) void
Free owned (text) memory in a row tuple.

### CRUD Operations
- `create(M, db, values) QueryError!i64` — INSERT a record; returns rowid
- `getById(M, db, gpa, id) QueryError!RowType(M)` — SELECT by primary key; returns `error.NotFound` if not found
- `all(M, db, gpa) QueryError!ArrayList(RowType(M))` — SELECT all rows
- `updateById(M, db, id, values) QueryError!void` — UPDATE by primary key
- `deleteById(M, db, id) QueryError!void` — DELETE by primary key
- `save(M, db, gpa, row) QueryError!i64` — INSERT or UPDATE; if `row[0]` (id) is 0, inserts and updates `row[0]`; otherwise updates

### Query Operations
- `filter(M, db, gpa, where, values) QueryError!ArrayList(RowType(M))` — SELECT with WHERE clause; values are bound as parameters (SQL injection safe)
- `filterLimitOffset(M, db, gpa, where, values, limit, offset) QueryError!ArrayList(RowType(M))` — paginated filtered query
- `filterOrderLimitOffset(M, db, gpa, where, values, order_by, limit, offset) QueryError!ArrayList(RowType(M))` — ordered paginated filtered query
- `order(M, db, gpa, order_by) QueryError!ArrayList(RowType(M))` — ORDER BY (standalone)
- `first(M, db, gpa, where, values) QueryError!?RowType(M)` — first matching row or null
- `count(M, db) QueryError!u64` — COUNT all rows

### QuerySet Builder
Chainable builder for complex queries:

```zig
var qs = QuerySet(Model).init(&db, gpa);
defer qs.deinit();
var results = try qs.filterBy("name LIKE ?", &.{.{ .text = "%foo%" }})
    .orderBy("name ASC")
    .limit(10)
    .offset(0)
    .exec();
```

Methods:
- `qs.init(db, gpa) Self` — create a QuerySet
- `qs.deinit()` — free where values
- `qs.filterBy(where, values) *Self` — set WHERE clause and values
- `qs.orderBy(order_by) *Self` — set ORDER BY clause
- `qs.limit(n) *Self` — set LIMIT
- `qs.offset(n) *Self` — set OFFSET
- `qs.exec() QueryError!ArrayList(RowType(M))` — execute the built query

### QueryError
Error set: `NotFound`, `NoRows`, `BindFailed`, `ExecFailed`, `PrepareFailed`, `StepFailed`, `ColumnFailed`, `AllocatorFailed`

## Migration
Database schema migration runner.

### Migration
- `id: i64` — unique migration ID
- `name: [:0]const u8` — migration name
- `up_sql: [:0]const u8` — forward SQL
- `down_sql: [:0]const u8` — rollback SQL

### MigrationStatus
- `id: i64` — migration ID
- `name: [:0]const u8` — migration name
- `applied: bool` — whether migration has been applied

### MigrationRunner
- `MigrationRunner.init(db) MigrationRunner` — create a runner
- `runner.ensureHistoryTable() MigrationError!void` — create `zypher_migrations` tracking table
- `runner.countApplied() MigrationError!u64` — count applied migrations
- `runner.migrate(migrations, io) MigrationError!void` — apply all pending migrations in order
- `runner.status(gpa, migrations) MigrationError![]MigrationStatus` — return migration application status
- `runner.rollback(migrations, n) MigrationError!void` — roll back the most recent `n` applied migrations (in reverse order) that have `down_sql`

### MigrationError
Error set: `PrepareFailed`, `StepFailed`, `ExecFailed`, `BindFailed`, `ColumnFailed`, `AllocatorFailed`, `NoMigrationsToRollback`

## Full Example

### SQLite (via config API)
```zig
const std = @import("std");
const zypher = @import("zypher");

const UserModel = zypher.orm.schema.Model("users", .{
    zypher.orm.schema.Field("id", .integer, .{ .primary = true }),
    zypher.orm.schema.Field("name", .text, .{ .required = true }),
    zypher.orm.schema.Field("age", .integer, .{}),
    zypher.orm.schema.Field("active", .boolean, .{ .default = .{ .boolean = true } }),
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // Open via config API (supports sqlite, postgres, mysql)
    var result = try zypher.orm.openDatabase(alloc, .{
        .sqlite = .{ .path = "app.db" },
    });
    defer result.open_db.close(alloc);

    const db = result.relational orelse return error.NoDatabase;
    try db.exec(UserModel.create_table_sql);

    // Insert a record
    const id = try zypher.orm.query.create(UserModel, db, &.{
        .{ .text = "Alice" },
        .{ .int = 30 },
        .{ .int = 1 },
    });

    // Fetch by ID
    const row = try zypher.orm.query.getById(UserModel, db, alloc, id);
    defer zypher.orm.query.freeRow(UserModel, alloc, &row);
    // row[0] == id, row[1] == "Alice", row[2] == 30, row[3] == true
}
```

### PostgreSQL
```zig
var result = try zypher.orm.openDatabase(alloc, .{
    .postgres = .{ .connstr = "postgresql://user:pass@localhost/mydb" },
});
defer result.open_db.close(alloc);
const db = result.relational orelse return error.NoDatabase;
```

### MySQL
```zig
var result = try zypher.orm.openDatabase(alloc, .{
    .mysql = .{ .db = "mydb", .user = "root", .pass = "secret" },
});
defer result.open_db.close(alloc);
const db = result.relational orelse return error.NoDatabase;
```
