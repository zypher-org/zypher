/// Phase 6 Integration Test — POST handler uses form, invalid returns 422, valid processes data.
const std = @import("std");
const zypher = @import("zypher");

const form = zypher.forms.form;
const FieldDef = form.FieldDef;
const Field = form.Field;

// ── Test form ────────────────────────────────────────────────────────────

const ContactFormFields = struct {
    name: FieldDef = Field("name", .text, .{ .required = true }),
    email: FieldDef = Field("email", .text, .{ .required = true }),
    message: FieldDef = Field("message", .text, .{ .required = true }),
};
const ContactForm = form.Form("ContactForm", ContactFormFields);

// ── Simulated POST handler ───────────────────────────────────────────────

fn handleFormPost(gpa: std.mem.Allocator, data: *std.StringHashMap([]const u8)) !u16 {
    var bound = try ContactForm.bind(gpa, data);
    defer bound.deinit();

    if (!bound.validate()) {
        return 422;
    }

    const cleaned = bound.cleanedData();
    _ = cleaned;
    return 200;
}

// ── Integration Tests ─────────────────────────────────────────────────────

test "forms integration: valid POST submission returns 200" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("name", "Alice");
    try data.put("email", "alice@example.com");
    try data.put("message", "Hello!");

    const status = try handleFormPost(std.testing.allocator, &data);
    try std.testing.expectEqual(@as(u16, 200), status);
}

test "forms integration: invalid POST returns 422 with field errors" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    try data.put("name", "Alice");
    try data.put("email", "not-an-email");
    try data.put("message", "");

    var bound = try ContactForm.bind(std.testing.allocator, &data);
    defer bound.deinit();

    const valid = bound.validate();
    try std.testing.expect(!valid);

    // Should have errors for email and message
    try std.testing.expect(bound.errors.contains("email"));
    try std.testing.expect(bound.errors.contains("message"));
}

test "forms integration: missing required fields returns 422" {
    var data = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer data.deinit();
    // All fields empty
    try data.put("name", "");
    try data.put("email", "");
    try data.put("message", "");

    const status = try handleFormPost(std.testing.allocator, &data);
    try std.testing.expectEqual(@as(u16, 422), status);
}
