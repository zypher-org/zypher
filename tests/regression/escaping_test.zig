const std = @import("std");
const zypher = @import("zypher");

const Template = zypher.template.renderer.Template;
const Context = zypher.template.renderer.Context;
const Value = zypher.template.renderer.Value;

fn renderToSlice(gpa: std.mem.Allocator, tmpl: *Template, ctx: *Context) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try tmpl.render(ctx, &aw.writer);
    var result = aw.toArrayList();
    return result.toOwnedSlice(gpa);
}

// Regression: auto-escaping cannot be bypassed — HTML special chars in
// variable output must always be escaped unless |safe is explicitly used.
test "regression: auto-escaping cannot be bypassed via variable" {
    const gpa = std.testing.allocator;

    var tmpl = try Template.fromSource(gpa, "{{ content }}");
    defer tmpl.deinit();

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("content", .{ .string = "<img src=x onerror=alert(1)>" });

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);

    // Must NOT contain raw < or >
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, "<"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, ">"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "&lt;"));
}

test "regression: auto-escaping applies to ampersand and quotes" {
    const gpa = std.testing.allocator;

    var tmpl = try Template.fromSource(gpa, "{{ val }}");
    defer tmpl.deinit();

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("val", .{ .string = "a=1&b=\"2\"" });

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);

    // Output should contain &amp; instead of raw &
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "&amp;"));
    // Should NOT contain raw & that isn't part of an entity
    try std.testing.expect(!std.mem.containsAtLeast(u8, output, 1, "&b"));
}

test "regression: |safe bypasses auto-escape explicitly" {
    const gpa = std.testing.allocator;

    var tmpl = try Template.fromSource(gpa, "{{ html | safe }}");
    defer tmpl.deinit();

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("html", .{ .string = "<b>bold</b>" });

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);

    // With |safe, raw HTML should pass through
    try std.testing.expectEqualStrings("<b>bold</b>", output);
}

test "regression: text nodes are not auto-escaped (only variables)" {
    const gpa = std.testing.allocator;

    var tmpl = try Template.fromSource(gpa, "<div>literal</div>");
    defer tmpl.deinit();

    var ctx = Context.init(gpa);
    defer ctx.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);

    // Text nodes pass through verbatim — no escaping
    try std.testing.expectEqualStrings("<div>literal</div>", output);
}

test "regression: unclosed variable expression does not crash" {
    const gpa = std.testing.allocator;

    const tmpl = Template.fromSource(gpa, "{{ unclosed");
    // Lexer should return error for unclosed tag
    try std.testing.expectError(error.UnclosedTag, tmpl);
}
