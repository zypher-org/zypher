const zypher = @import("zypher");
const schema = zypher.orm.schema;

pub const Resource = struct {
    id: i64,
    name: []const u8,
};

pub fn load() Resource {
    return .{ .id = 1, .name = "{{project_name}}" };
}

pub const ManagedItemFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    name: schema.FieldDef = schema.Field("name", .text, .{ .required = true }),
    description: schema.FieldDef = schema.Field("description", .text, .{}),
};
pub const ManagedItem = schema.Model("managed_items", ManagedItemFields);
