const zypher = @import("zypher");

const schema = zypher.orm.schema;

pub const NoteFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    title: schema.FieldDef = schema.Field("title", .text, .{ .required = true }),
    body: schema.FieldDef = schema.Field("body", .text, .{ .required = true }),
    tags: schema.FieldDef = schema.Field("tags", .text, .{}),
    pinned: schema.FieldDef = schema.Field("pinned", .boolean, .{ .default = .{ .boolean = false } }),
    archived: schema.FieldDef = schema.Field("archived", .boolean, .{ .default = .{ .boolean = false } }),
    created_at: schema.FieldDef = schema.Field("created_at", .integer, .{ .required = true }),
    updated_at: schema.FieldDef = schema.Field("updated_at", .integer, .{ .required = true }),
};

pub const Note = schema.Model("notes", NoteFields);
pub const NoteRow = zypher.orm.query.RowType(Note);

pub const NoteInput = struct {
    title: []const u8,
    body: []const u8,
    tags: []const u8 = "",
    pinned: bool = false,
    archived: bool = false,
};

test "note schema exposes notes table" {
    try @import("std").testing.expectEqualStrings("notes", Note.table_name);
}
