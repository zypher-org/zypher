const zypher = @import("zypher");

const schema = zypher.orm.schema;

pub const Page = struct {
    title: []const u8,
    body: []const u8,
};

pub fn home() Page {
    return .{ .title = "{{project_name}}", .body = "MVC scaffold is running." };
}

pub const ManagedItemFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    name: schema.FieldDef = schema.Field("name", .text, .{ .required = true }),
    description: schema.FieldDef = schema.Field("description", .text, .{}),
};

pub const ManagedItem = schema.Model("managed_items", ManagedItemFields);
