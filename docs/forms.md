# Forms API

Comptime-defined form structs with validation. Forms are defined at compile time and bound to request data at runtime.

## FieldKind
Enum determining how values are parsed and validated:
- `text` — string value
- `integer` — parsed as `i64`
- `boolean` — parsed from "true", "1"
- `file` — references multipart upload data

## FieldDef
- `name: [:0]const u8` — field name
- `kind: FieldKind` — field kind
- `required: bool = false` — whether field is required
- `validator: ?*const fn ([]const u8) ?[]const u8 = null` — custom validator function; returns `null` on success or an error message string

## Field(name, kind, options) FieldDef
Comptime field constructor.

```zig
const myField = Field("email", .text, .{ .required = true });
```

Options:
- `required: bool = false`
- `validator: ?*const fn ([]const u8) ?[]const u8 = null`

## DataType(Fields) type
Generate a tuple type matching the field order and kinds:
- `.text` → `[]const u8`
- `.integer` → `i64`
- `.boolean` → `bool`
- `.file` → `[]const u8`

## Form(name, Fields) type
Generate a Form type from a name and fields struct.

### Generated Type Constants
- `Form.FormName` — the form name
- `Form.FieldsType` — the raw fields type
- `Form.Data` — the cleaned data tuple type
- `Form.fields_len` — number of fields

### Generated Type Methods
- `Form.fieldAt(i) FieldDef` — get field definition by index (comptime)
- `Form.bind(gpa, data) !BoundForm` — bind form data from a `*std.StringHashMap([]const u8)` (from POST body parsing)
- `Form.bindRequest(gpa, req) !BoundForm` — bind form data from a `*Request`; text fields use `req.formValue()`, file fields use `req.file()`

### BoundForm
A bound form with values and validation errors.

- `boundForm.getValue(field_name) []const u8` — get raw string value for a field
- `boundForm.validate() bool` — validate all fields; returns true if all pass
  - Checks required fields (non-empty)
  - Runs custom validators
  - Auto-validates email format for fields named "email"
- `boundForm.cleanedData() Data` — return typed cleaned data after validation (parses integers, booleans)
- `boundForm.csrfField(io, req) ![]u8` — get an owned CSRF hidden input backed by the request session
- `boundForm.deinit()` — free values and errors maps

## Validators
Built-in validation functions.

- `email(value) ?[]const u8` — validate email format; returns error message or null
- `required(value) ?[]const u8` — validate non-empty
- `requiredOptional(value) ?[]const u8` — validate non-empty if value is present; passes null through
- `minLength(n) *const fn ([]const u8) ?[]const u8` — minimum length validator factory
- `maxLength(n) *const fn ([]const u8) ?[]const u8` — maximum length validator factory
- `regex(pattern) *const fn ([]const u8) ?[]const u8` — glob-style pattern validator factory (`*` = any sequence, `?` = any char)
- `url() *const fn ([]const u8) ?[]const u8` — validate URL format
- `min(T, threshold) fn (T) ?[]const u8` — minimum value validator for numeric types
- `max(T, threshold) fn (T) ?[]const u8` — maximum value validator for numeric types
- `choices(valid_values) fn ([]const u8) ?[]const u8` — validate value is in a list
- `custom(T, validate_fn) fn (T) ?[]const u8` — wrap an arbitrary validator function

## Full Example
```zig
const std = @import("std");
const zypher = @import("zypher");

const ContactForm = zypher.forms.form.Form("contact", .{
    zypher.forms.form.Field("name", .text, .{ .required = true }),
    zypher.forms.form.Field("email", .text, .{ .required = true }),
    zypher.forms.form.Field("message", .text, .{ .required = true, .validator = zypher.forms.validators.minLength(10) }),
});

pub fn handleForm(req: *zypher.core.Request, res: *zypher.core.Response) void {
    var bound = ContactForm.bindRequest(res.allocator, req) catch return;
    defer bound.deinit();

    if (!bound.validate()) {
        const name = bound.getValue("name");
        // Render form with errors
        return;
    }

    const data = bound.cleanedData();
    // data[0] == name ([]const u8)
    // data[1] == email ([]const u8)
    // data[2] == message ([]const u8)
}
```
