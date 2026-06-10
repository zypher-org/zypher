# ORM API

## SQLite
Low-level SQLite3 bindings.

- `Db.open(gpa, path)` — Open or create a database
- `Db.close()` — Close the database
- `db.prepare(sql)` — Prepare a statement
- `db.exec(sql)` — Execute SQL directly
- `db.lastInsertRowId()` — Get last inserted rowid

## Schema
Comptime model definition.

- `Model(name, fields)` — Define a model type
- `Field(name, kind, options)` — Define a field
- Model fields: `id`, `table_name`, `fields_len`, `fieldAt(i)`, `create_table_sql`,
  `insert_sql`, `select_all_sql`, `select_by_id_sql`, `update_by_id_sql`, `delete_by_id_sql`

## Query
Runtime query execution.

- `create(M, db, values)` — INSERT a record
- `getById(M, db, gpa, id)` — SELECT by primary key
- `all(M, db, gpa)` — SELECT all rows
- `filter(M, db, gpa, where, values)` — SELECT with WHERE
- `filterLimitOffset(M, db, gpa, where, values, limit, offset)` — Paginated filter
- `filterOrderLimitOffset(M, db, gpa, where, values, order_by, limit, offset)` — Ordered paginated filter
- `order(M, db, gpa, order_by)` — ORDER BY (standalone)
- `first(M, db, gpa, where, values)` — SELECT first matching row
- `count(M, db)` — COUNT all rows
- `updateById(M, db, id, values)` — UPDATE by primary key
- `deleteById(M, db, id)` — DELETE by primary key
- `save(M, db, gpa, row)` — INSERT or UPDATE

### QuerySet Builder
```zig
var qs = QuerySet(Model).init(&db, gpa);
defer qs.deinit();
var results = qs.filterBy("name LIKE ?", &.{.{ .text = "%foo%" }})
    .orderBy("name ASC")
    .limit(10)
    .offset(0)
    .exec();
```

## Migration
Manage database schema migrations.

- `MigrationRunner.init(db)` — Create a runner
- `runner.ensureHistoryTable()` — Create migration tracking table
- `runner.countApplied()` — Count applied migrations
- `runner.migrate(migrations)` — Apply pending migrations
- `runner.status(gpa, migrations)` — Return migration application status
- `runner.rollback(migrations, n)` — Roll back the most recent `n` migrations that provide `down_sql`
