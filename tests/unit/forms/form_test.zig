const std = @import("std");
const form = @import("zypher").forms.form;
const validators = @import("zypher").forms.validators;

const Form = form.Form;
const FieldDef = form.FieldDef;
const Field = form.Field;
const Request = @import("zypher").core.Request;

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

const UploadFormFields = struct {
    title: FieldDef = Field("title", .text, .{ .required = true }),
    attachment: FieldDef = Field("attachment", .file, .{ .required = true }),
};
const UploadForm = Form("UploadForm", UploadFormFields);

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

test "form: bindRequest populates file field from multipart request upload" {
    var req: Request = .{
        .method = .post,
        .path = "/upload",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
        .files = std.StringHashMap(Request.FileUpload).init(std.testing.allocator),
        .files_owned = true,
    };
    defer req.deinit();

    try req.query.put("title", "Report");
    try req.files.put(try std.testing.allocator.dupe(u8, "attachment"), .{
        .filename = try std.testing.allocator.dupe(u8, "report.txt"),
        .content_type = try std.testing.allocator.dupe(u8, "text/plain"),
        .data = try std.testing.allocator.dupe(u8, "file bytes"),
    });

    var bound = try UploadForm.bindRequest(std.testing.allocator, &req);
    defer bound.deinit();
    try std.testing.expect(bound.validate());

    const cleaned = bound.cleanedData();
    try std.testing.expectEqualStrings("Report", cleaned[0]);
    try std.testing.expectEqualStrings("file bytes", cleaned[1]);
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
    try std.testing.expectEqualStrings("alice", cleaned[0]);
    try std.testing.expectEqualStrings("alice@example.com", cleaned[1]);
    try std.testing.expectEqual(@as(i64, 30), cleaned[2]);
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
    try std.testing.expectEqual(@as(i64, 0), cleaned[2]);
}
