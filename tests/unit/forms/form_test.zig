const std = @import("std");
const form = @import("zypher").forms.form;
const validators = @import("zypher").forms.validators;

const Form = form.Form;
const FieldDef = form.FieldDef;
const Field = form.Field;

// ── Test form definitions ────────────────────────────────────────────────

const LoginFormFields = struct {
    username: FieldDef = Field("username", .text, .{ .required = true }),
    password: FieldDef = Field("password", .text, .{ .required = true }),
};
const LoginForm = Form("LoginForm", LoginFormFields);

const RegistrationFormFields = struct {
    username: FieldDef = Field("username", .text, .{ .required = true }),
    email: FieldDef = Field("email", .text, .{ .required = true }),
    age: FieldDef = Field("age", .integer, .{}),
};
const RegistrationForm = Form("RegistrationForm", RegistrationFormFields);

// ── bind ──────────────────────────────────────────────────────────────────

test "form: bind populates fields from key-value data" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "alice");
    try data.put("password", "secret123");

    var bound = try LoginForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    try std.testing.expectEqualStrings("alice", bound.getValue("username"));
    try std.testing.expectEqualStrings("secret123", bound.getValue("password"));
}

test "form: bind with missing optional field returns empty string" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "bob");
    try data.put("email", "bob@ex.com");
    // age not provided

    var bound = try RegistrationForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    try std.testing.expectEqualStrings("", bound.getValue("age"));
}

// ── validate ──────────────────────────────────────────────────────────────

test "form: validate returns true when all required fields present" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "alice");
    try data.put("password", "secret123");

    var bound = try LoginForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    try std.testing.expect(bound.validate());
    try std.testing.expect(bound.errors.count() == 0);
}

test "form: validate returns false when required field missing" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "alice");
    // password missing

    var bound = try LoginForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    try std.testing.expect(!bound.validate());
    try std.testing.expect(bound.errors.count() > 0);
    try std.testing.expect(bound.errors.contains("password"));
}

test "form: validate with email validator" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "alice");
    try data.put("email", "not-an-email");
    try data.put("age", "25");

    var bound = try RegistrationForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    // Registration form has email validator
    try std.testing.expect(!bound.validate());
    try std.testing.expect(bound.errors.contains("email"));
}

// ── errors ────────────────────────────────────────────────────────────────

test "form: errors map contains field-level error messages" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    // Both required fields empty
    try data.put("username", "");
    try data.put("password", "");

    var bound = try LoginForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    try std.testing.expect(!bound.validate());
    const username_err = bound.errors.get("username");
    try std.testing.expect(username_err != null);
    try std.testing.expect(username_err.?.len > 0);
}

// ── cleanedData ──────────────────────────────────────────────────────────

test "form: cleanedData returns typed values after validation" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "alice");
    try data.put("email", "alice@example.com");
    try data.put("age", "30");

    var bound = try RegistrationForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    try std.testing.expect(bound.validate());

    const cleaned = bound.cleanedData();
    try std.testing.expectEqualStrings("alice", cleaned.username);
    try std.testing.expectEqualStrings("alice@example.com", cleaned.email);
    try std.testing.expectEqual(@as(i64, 30), cleaned.age);
}

test "form: cleanedData with invalid integer returns 0" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("username", "bob");
    try data.put("email", "bob@ex.com");
    try data.put("age", "not-a-number");

    var bound = try RegistrationForm.bind(std.testing.allocator, &data);
    defer bound.deinit();
    // Validation may pass (age is optional), but integer parsing fails
    const cleaned = bound.cleanedData();
    try std.testing.expectEqual(@as(i64, 0), cleaned.age);
}
