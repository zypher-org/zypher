/// zypher ORM — compile-time schema definitions and SQL generation.
const std = @import("std");
const iface = @import("driver/interface.zig");
const SqliteDialect = iface.SqliteDialect;

// ── Field types ───────────────────────────────────────────────────────────

pub const FieldKind = enum {
    integer,
    float,
    text,
    boolean,
    timestamp,
};

pub const DefaultValue = union(FieldKind) {
    integer: i64,
    float: f64,
    text: [:0]const u8,
    boolean: bool,
    timestamp: i64,
};

pub const FieldOptions = struct {
    primary: bool = false,
    required: bool = false,
    unique: bool = false,
    foreign: ?[:0]const u8 = null,
    default: ?DefaultValue = null,
};

pub const FieldDef = struct {
    name: [:0]const u8,
    kind: FieldKind,
    primary: bool,
    required: bool,
    unique: bool,
    foreign: ?[:0]const u8,
    default: ?DefaultValue,
};

/// Comptime field constructor.
pub fn Field(
    comptime name: [:0]const u8,
    comptime kind: FieldKind,
    comptime opts: FieldOptions,
) FieldDef {
    return .{
        .name = name,
        .kind = kind,
        .primary = opts.primary,
        .required = opts.required,
        .unique = opts.unique,
        .foreign = opts.foreign,
        .default = opts.default,
    };
}

// ── Model config ──────────────────────────────────────────────────────────

pub const ModelOptions = struct {
    table: [:0]const u8,
    fields: []const FieldDef,
};

// ── Dialect helpers (comptime) ────────────────────────────────────────────

fn isPostgres(comptime dialect: iface.Dialect) bool {
    return comptime std.mem.eql(u8, dialect.float_type, "DOUBLE PRECISION");
}

fn migrationIntType(comptime dialect: iface.Dialect) [:0]const u8 {
    if (comptime isPostgres(dialect)) return "BIGINT";
    if (comptime std.mem.eql(u8, dialect.timestamp_now, "UNIX_TIMESTAMP()")) return "BIGINT";
    return "INTEGER";
}

fn fieldSqlType(comptime kind: FieldKind, comptime dialect: iface.Dialect) []const u8 {
    return comptime switch (kind) {
        .integer => "INTEGER",
        .float => dialect.float_type,
        .text => dialect.text_type,
        .boolean => dialect.bool_type,
        .timestamp => if (isPostgres(dialect)) "BIGINT" else "INTEGER",
    };
}

fn placeholderStr(comptime dialect: iface.Dialect, comptime slot: usize) [:0]const u8 {
    if (comptime isPostgres(dialect)) {
        return std.fmt.comptimePrint("${d}", .{slot});
    } else {
        return "?";
    }
}

// ── Model ─────────────────────────────────────────────────────────────────

/// Define an ORM model from a table name and a struct type whose
/// comptime-known default field values are FieldDef instances.
pub fn Model(comptime table: [:0]const u8, comptime Fields: type) type {
    const field_names = std.meta.fieldNames(Fields);
    const fields_instance: Fields = .{};

    return struct {
        pub const table_name = table;
        pub const fields_len = field_names.len;

        pub fn fieldAt(comptime i: usize) FieldDef {
            return @field(fields_instance, field_names[i]);
        }

        pub const insert_field_count: comptime_int = blk: {
            var count: comptime_int = 0;
            for (field_names) |name| {
                if (!@field(fields_instance, name).primary) count += 1;
            }
            break :blk count;
        };

        pub fn createTableSql(comptime dialect: iface.Dialect) [:0]const u8 {
            return comptime blk: {
                var result: [:0]const u8 = "CREATE TABLE IF NOT EXISTS " ++ table ++ " (";
                for (field_names, 0..) |name, i| {
                    if (i > 0) result = result ++ ", ";
                    const f = @field(fields_instance, name);
                    result = result ++ f.name ++ " ";
                    if (f.primary) {
                        result = result ++ dialect.pk_type;
                    } else {
                        result = result ++ fieldSqlType(f.kind, dialect);
                        if (f.required) result = result ++ " NOT NULL";
                        if (f.unique) result = result ++ " UNIQUE";
                        if (f.foreign) |fk| result = result ++ " REFERENCES " ++ fk;
                        if (f.default) |dv| {
                            result = result ++ " DEFAULT " ++ switch (dv) {
                                .integer => |v| std.fmt.comptimePrint("{d}", .{v}),
                                .float => |v| std.fmt.comptimePrint("{d}", .{v}),
                                .text => |v| "'" ++ v ++ "'",
                                .boolean => |v| if (v) "1" else "0",
                                .timestamp => |v| std.fmt.comptimePrint("{d}", .{v}),
                            };
                        }
                    }
                }
                result = result ++ ")";
                break :blk result;
            };
        }

        pub const create_table_sql: [:0]const u8 = createTableSql(SqliteDialect);

        pub const drop_table_sql: [:0]const u8 = "DROP TABLE IF EXISTS " ++ table;

        pub fn insertSql(comptime dialect: iface.Dialect) [:0]const u8 {
            return comptime blk: {
                var cols: [:0]const u8 = "";
                var placeholders: [:0]const u8 = "";
                var slot: usize = 1;
                for (field_names) |name| {
                    const f = @field(fields_instance, name);
                    if (f.primary) continue;
                    if (cols.len > 0) {
                        cols = cols ++ ",";
                        placeholders = placeholders ++ ",";
                    }
                    cols = cols ++ f.name;
                    placeholders = placeholders ++ placeholderStr(dialect, slot);
                    slot += 1;
                }
                break :blk "INSERT INTO " ++ table ++ " (" ++ cols ++ ") VALUES (" ++ placeholders ++ ")";
            };
        }

        pub const insert_sql: [:0]const u8 = insertSql(SqliteDialect);

        pub const select_all_sql: [:0]const u8 = blk: {
            var result: [:0]const u8 = "SELECT ";
            for (field_names, 0..) |name, i| {
                if (i > 0) result = result ++ ", ";
                result = result ++ @field(fields_instance, name).name;
            }
            break :blk result ++ " FROM " ++ table;
        };

        pub const primary_key_name: [:0]const u8 = blk: {
            var found: [:0]const u8 = "id";
            for (field_names) |name| {
                const f = @field(fields_instance, name);
                if (f.primary) {
                    found = f.name;
                    break;
                }
            }
            break :blk found;
        };

        pub const primary_key_index: usize = blk: {
            var found: usize = 0;
            for (field_names, 0..) |name, i| {
                if (@field(fields_instance, name).primary) {
                    found = i;
                    break;
                }
            }
            break :blk found;
        };

        pub fn selectByIdSql(comptime dialect: iface.Dialect) [:0]const u8 {
            return comptime blk: {
                break :blk select_all_sql ++ " WHERE " ++ primary_key_name ++ " = " ++ placeholderStr(dialect, 1);
            };
        }

        pub const select_by_id_sql: [:0]const u8 = selectByIdSql(SqliteDialect);

        pub fn updateByIdSql(comptime dialect: iface.Dialect) [:0]const u8 {
            return comptime blk: {
                var result: [:0]const u8 = "UPDATE " ++ table ++ " SET ";
                var first = true;
                var slot: usize = 1;
                for (field_names) |name| {
                    const f = @field(fields_instance, name);
                    if (f.primary) continue;
                    if (!first) result = result ++ ", ";
                    first = false;
                    result = result ++ f.name ++ " = " ++ placeholderStr(dialect, slot);
                    slot += 1;
                }
                break :blk result ++ " WHERE " ++ primary_key_name ++ " = " ++ placeholderStr(dialect, slot);
            };
        }

        pub const update_by_id_sql: [:0]const u8 = updateByIdSql(SqliteDialect);

        pub const delete_by_id_sql: [:0]const u8 = "DELETE FROM " ++ table ++ " WHERE " ++ primary_key_name ++ " = ?";
    };
}

/// Generate dialect-correct DDL for the zypher_migrations history table.
pub fn migrationHistoryTableSql(comptime dialect: iface.Dialect) [:0]const u8 {
    return comptime blk: {
        const int_type = migrationIntType(dialect);
        const ts_default = dialect.timestamp_now;
        break :blk "CREATE TABLE IF NOT EXISTS zypher_migrations (id " ++ int_type ++ " PRIMARY KEY, name TEXT NOT NULL, applied_at " ++ int_type ++ " NOT NULL DEFAULT (" ++ ts_default ++ "))";
    };
}

test {
    std.testing.refAllDecls(@This());
}
