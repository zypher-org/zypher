const std = @import("std");
const renderer = @import("zypher").template.renderer;

const Value = renderer.Value;
const Context = renderer.Context;
const Template = renderer.Template;

fn renderToSlice(gpa: std.mem.Allocator, tmpl: *Template, ctx: *Context) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try tmpl.render(ctx, &aw.writer);
    var result = aw.toArrayList();
    return result.toOwnedSlice(gpa);
}

test "renderer: render plain string" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    var tmpl = try Template.fromSource(gpa, "hello world");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("hello world", output);
}

test "renderer: render {{ name }} with context" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("name", .{ .string = "zypher" });

    var tmpl = try Template.fromSource(gpa, "Hello {{ name }}!");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Hello zypher!", output);
}

test "renderer: auto-escape <script> in variable output" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("user_input", .{ .string = "<script>alert('xss')</script>" });

    var tmpl = try Template.fromSource(gpa, "{{ user_input }}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;", output);
}

test "renderer: render {% if %} branch — true case" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("show", .{ .bool = true });

    var tmpl = try Template.fromSource(gpa, "{% if show %}visible{% endif %}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("visible", output);
}

test "renderer: render {% if %} branch — false case" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("show", .{ .bool = false });

    var tmpl = try Template.fromSource(gpa, "{% if show %}visible{% else %}hidden{% endif %}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("hidden", output);
}

test "renderer: render {% for %} loop over list" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    const items = &[_]Value{
        .{ .string = "a" },
        .{ .string = "b" },
        .{ .string = "c" },
    };
    try ctx.put("items", .{ .list = items });

    var tmpl = try Template.fromSource(gpa, "{% for item in items %}{{ item }} {% endfor %}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("a b c ", output);
}

test "renderer: missing variable in context renders as empty string" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    var tmpl = try Template.fromSource(gpa, "Hello {{ missing }}!");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Hello !", output);
}

test "renderer: nested if inside for loop" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    const items = &[_]Value{
        .{ .string = "apple" },
        .{ .string = "banana" },
    };
    try ctx.put("items", .{ .list = items });
    try ctx.put("highlight", .{ .bool = true });

    var tmpl = try Template.fromSource(gpa, "{% for item in items %}{% if highlight %}*{{ item }}* {% endif %}{% endfor %}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("*apple* *banana* ", output);
}

test "renderer: render integer and float values" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("count", .{ .int = 42 });
    try ctx.put("price", .{ .float = 9.99 });

    var tmpl = try Template.fromSource(gpa, "Count: {{ count }}, Price: {{ price }}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Count: 42, Price: 9.99", output);
}
