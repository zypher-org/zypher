/// zypher ORM — compile-time schema definitions and SQL generation.
const std = @import("std");

// ── Field types ───────────────────────────────────────────────────────────

pub const FieldKind = enum {
    integer,
    float,
    text,
    boolean,
};

pub const DefaultValue = union(FieldKind) {
    integer: i64,
    float: f64,
    text: [:0]const u8,
    boolean: bool,
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

// ── Model ─────────────────────────────────────────────────────────────────

/// Define an ORM model from a table name and a struct type whose
/// comptime-known default field values are FieldDef instances.
pub fn Model(comptime table: [:0]const u8, comptime Fields: type) type {
    const fields_info = @typeInfo(Fields).@"struct";
    // Instantiate the struct to get default field values
    const fields_instance: Fields = .{};

    return struct {
        pub const table_name = table;
        pub const fields_len = fields_info.fields.len;

        /// Get field definition by index (comptime).
        pub fn fieldAt(comptime i: usize) FieldDef {
            return @field(fields_instance, fields_info.fields[i].name);
        }

        /// Number of non-primary-key fields (for INSERT).
        pub const insert_field_count: comptime_int = blk: {
            var count: comptime_int = 0;
            for (fields_info.fields) |fi| {
                if (!@field(fields_instance, fi.name).primary) count += 1;
            }
            break :blk count;
        };

        /// Generate CREATE TABLE IF NOT EXISTS SQL.
        pub const create_table_sql: [:0]const u8 = blk: {
            var result: [:0]const u8 = "CREATE TABLE IF NOT EXISTS " ++ table ++ " (";
            for (fields_info.fields, 0..) |fi, i| {
                if (i > 0) result = result ++ ", ";
                const f = @field(fields_instance, fi.name);
                result = result ++ f.name ++ " ";
                result = result ++ switch (f.kind) {
                    .integer => "INTEGER",
                    .float => "REAL",
                    .text => "TEXT",
                    .boolean => "BOOLEAN",
                };
                if (f.primary) {
                    result = result ++ " PRIMARY KEY";
                } else {
                    if (f.required) result = result ++ " NOT NULL";
                    if (f.unique) result = result ++ " UNIQUE";
                    if (f.foreign) |fk| result = result ++ " REFERENCES " ++ fk;
                    if (f.default) |dv| {
                        result = result ++ " DEFAULT " ++ switch (dv) {
                            .integer => |v| std.fmt.comptimePrint("{d}", .{v}),
                            .float => |v| std.fmt.comptimePrint("{d}", .{v}),
                            .text => |v| "'" ++ v ++ "'",
                            .boolean => |v| if (v) "1" else "0",
                        };
                    }
                }
            }
            result = result ++ ")";
            break :blk result;
        };

        /// Generate DROP TABLE IF EXISTS SQL.
        pub const drop_table_sql: [:0]const u8 = "DROP TABLE IF EXISTS " ++ table;

        /// Generate INSERT SQL (excludes auto-increment primary key).
        pub const insert_sql: [:0]const u8 = blk: {
            var cols: [:0]const u8 = "";
            var placeholders: [:0]const u8 = "";
            for (fields_info.fields) |fi| {
                const f = @field(fields_instance, fi.name);
                if (f.primary) continue;
                if (cols.len > 0) {
                    cols = cols ++ ",";
                    placeholders = placeholders ++ ",";
                }
                cols = cols ++ f.name;
                placeholders = placeholders ++ "?";
            }
            break :blk "INSERT INTO " ++ table ++ " (" ++ cols ++ ") VALUES (" ++ placeholders ++ ")";
        };

        /// Generate SELECT all columns SQL.
        pub const select_all_sql: [:0]const u8 = blk: {
            var result: [:0]const u8 = "SELECT ";
            for (fields_info.fields, 0..) |fi, i| {
                if (i > 0) result = result ++ ", ";
                result = result ++ @field(fields_instance, fi.name).name;
            }
            break :blk result ++ " FROM " ++ table;
        };

        /// Generate SELECT by primary key SQL.
        pub const select_by_id_sql: [:0]const u8 = select_all_sql ++ " WHERE id = ?";

        /// Generate UPDATE by primary key SQL.
        pub const update_by_id_sql: [:0]const u8 = blk: {
            var result: [:0]const u8 = "UPDATE " ++ table ++ " SET ";
            var first = true;
            for (fields_info.fields) |fi| {
                const f = @field(fields_instance, fi.name);
                if (f.primary) continue;
                if (!first) result = result ++ ", ";
                first = false;
                result = result ++ f.name ++ " = ?";
            }
            break :blk result ++ " WHERE id = ?";
        };

        /// Generate DELETE by primary key SQL.
        pub const delete_by_id_sql: [:0]const u8 = "DELETE FROM " ++ table ++ " WHERE id = ?";
    };
}

test {
    std.testing.refAllDecls(@This());
}
