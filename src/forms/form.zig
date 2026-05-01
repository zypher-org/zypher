/// zypher forms — comptime-defined form structs with validation.
const std = @import("std");
const validators = @import("validators.zig");

const log = std.log.scoped(.form);

/// Field kind — determines how values are parsed and validated.
pub const FieldKind = enum { text, integer, boolean };

/// Field definition — used as default struct field values.
pub const FieldDef = struct {
    name: [:0]const u8,
    kind: FieldKind,
    required: bool = false,
    validator: ?*const fn ([]const u8) ?[]const u8 = null,
};

/// Comptime field constructor.
pub fn Field(comptime name: [:0]const u8, comptime kind: FieldKind, comptime options: struct {
    required: bool = false,
    validator: ?*const fn ([]const u8) ?[]const u8 = null,
}) FieldDef {
    return .{
        .name = name,
        .kind = kind,
        .required = options.required,
        .validator = options.validator,
    };
}

/// Data type returned by cleanedData(). Fields match the form definition order.
pub fn DataType(comptime F: type) type {
    comptime {
        const info = @typeInfo(F).@"struct";
        var names: [info.fields.len][]const u8 = undefined;
        var types: [info.fields.len]type = undefined;
        var attrs: [info.fields.len]std.builtin.Type.StructField.Attributes = undefined;
        for (info.fields, 0..) |field, i| {
            const f = @field(@as(F, .{}), field.name);
            names[i] = f.name;
            types[i] = switch (f.kind) {
                .text => []const u8,
                .integer => i64,
                .boolean => bool,
            };
            attrs[i] = .{
                .@"align" = null,
                .@"comptime" = false,
                .default_value_ptr = null,
            };
        }
        return @Struct(.auto, null, &names, &types, &attrs);
    }
}

/// Generate a Form type from a comptime fields struct.
pub fn Form(comptime name: [:0]const u8, comptime Fields: type) type {
    return struct {
        pub const FormName = name;
        pub const FieldsType = Fields;
        pub const Data = DataType(FieldsType);
        pub const fields_len = @typeInfo(FieldsType).@"struct".fields.len;

        const Self = @This();

        /// Get a FieldDef by index.
        pub fn fieldAt(comptime i: usize) FieldDef {
            const info = @typeInfo(FieldsType).@"struct";
            return @field(@as(FieldsType, .{}), info.fields[i].name);
        }

        /// Bind form data from a string map (typically from POST body parsing).
        pub fn bind(gpa: std.mem.Allocator, data: *std.StringHashMap([]const u8)) !BoundForm {
            var values = std.StringHashMap([]const u8).init(gpa);
            errdefer values.deinit();

            inline for (0..fields_len) |i| {
                const f = comptime fieldAt(i);
                const val = data.get(f.name) orelse "";
                try values.put(f.name, val);
            }

            return BoundForm{
                .gpa = gpa,
                .values = values,
                .errors = std.StringHashMap([]const u8).init(gpa),
            };
        }

        /// A bound form with values and validation errors.
        pub const BoundForm = struct {
            gpa: std.mem.Allocator,
            values: std.StringHashMap([]const u8),
            errors: std.StringHashMap([]const u8),

            /// Get the raw string value for a field.
            pub fn getValue(self: *BoundForm, field_name: []const u8) []const u8 {
                return self.values.get(field_name) orelse "";
            }

            /// Validate all fields. Returns true if all pass.
            pub fn validate(self: *BoundForm) bool {
                self.errors.deinit();
                self.errors = std.StringHashMap([]const u8).init(self.gpa);
                var all_valid = true;

                inline for (0..fields_len) |i| {
                    const f = comptime fieldAt(i);
                    const value = self.getValue(f.name);

                    // Required check
                    if (f.required and value.len == 0) {
                        _ = self.errors.fetchPut(f.name, "this field is required") catch {};
                        all_valid = false;
                    } else {
                        // Custom validator
                        if (f.validator) |v| {
                            if (v(value)) |err_msg| {
                                _ = self.errors.fetchPut(f.name, err_msg) catch {};
                                all_valid = false;
                            }
                        }

                        // Built-in email validation for text fields named "email"
                        if (std.mem.eql(u8, f.name, "email") and value.len > 0) {
                            if (validators.email(value)) |err_msg| {
                                _ = self.errors.fetchPut(f.name, err_msg) catch {};
                                all_valid = false;
                            }
                        }
                    }
                }

                return all_valid;
            }

            /// Return typed cleaned data after validation.
            pub fn cleanedData(self: *BoundForm) Data {
                var result: Data = undefined;
                const data_fields = @typeInfo(Data).@"struct".fields;
                inline for (0..fields_len) |i| {
                    const f = comptime fieldAt(i);
                    const fname = data_fields[i].name;
                    const value = self.getValue(f.name);
                    switch (f.kind) {
                        .text => @field(result, fname) = value,
                        .integer => @field(result, fname) = std.fmt.parseInt(i64, value, 10) catch 0,
                        .boolean => @field(result, fname) = (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1")),
                    }
                }
                return result;
            }

            /// Free all resources.
            pub fn deinit(self: *BoundForm) void {
                self.values.deinit();
                self.errors.deinit();
            }
        };
    };
}

test {
    std.testing.refAllDecls(@This());
}
