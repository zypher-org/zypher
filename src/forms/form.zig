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
        const field_names = std.meta.fieldNames(F);
        var types: [field_names.len]type = undefined;
        for (field_names, 0..) |field_name, i| {
            const f = @field(@as(F, .{}), field_name);
            types[i] = switch (f.kind) {
                .text => []const u8,
                .integer => i64,
                .boolean => bool,
            };
        }
        return @Tuple(&types);
    }
}

/// Generate a Form type from a comptime fields struct.
pub fn Form(comptime name: [:0]const u8, comptime Fields: type) type {
    return struct {
        pub const FormName = name;
        pub const FieldsType = Fields;
        pub const Data = DataType(FieldsType);
        pub const fields_len = std.meta.fieldNames(FieldsType).len;

        const Self = @This();

        /// Get a FieldDef by index.
        pub fn fieldAt(comptime i: usize) FieldDef {
            const names = std.meta.fieldNames(FieldsType);
            return @field(@as(FieldsType, .{}), names[i]);
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
                inline for (0..fields_len) |i| {
                    const f = comptime fieldAt(i);
                    const value = self.getValue(f.name);
                    switch (f.kind) {
                        .text => result[i] = value,
                        .integer => result[i] = std.fmt.parseInt(i64, value, 10) catch 0,
                        .boolean => result[i] = (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1")),
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
