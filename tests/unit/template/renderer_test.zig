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

test "renderer: compact safe filter bypasses escaping" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("content", .{ .string = "<p>No posts yet</p>" });

    var tmpl = try Template.fromSource(gpa, "{{ content|safe }}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("<p>No posts yet</p>", output);
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

test "renderer: dot access on map value" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    var person_ctx = try gpa.create(Context);
    person_ctx.* = Context.init(gpa);
    try person_ctx.put("name", .{ .string = "Alice" });
    try ctx.put("person", .{ .map = person_ctx });

    var tmpl = try Template.fromSource(gpa, "Hello {{ person.name }}!");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("Hello Alice!", output);

    person_ctx.deinit();
    gpa.destroy(person_ctx);
}

test "renderer: index access on list value" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    const items = &[_]Value{
        .{ .string = "first" },
        .{ .string = "second" },
        .{ .string = "third" },
    };
    try ctx.put("items", .{ .list = items });

    var tmpl = try Template.fromSource(gpa, "{{ items.0 }} {{ items.2 }}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("first third", output);
}

test "renderer: forloop.counter0 and forloop.counter" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    const items = &[_]Value{
        .{ .string = "a" },
        .{ .string = "b" },
    };
    try ctx.put("items", .{ .list = items });

    var tmpl = try Template.fromSource(gpa, "{% for item in items %}{{ forloop.counter0 }}-{{ forloop.counter }} {% endfor %}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("0-1 1-2 ", output);
}

test "renderer: forloop.first and forloop.last" {
    const gpa = std.testing.allocator;
    var ctx = Context.init(gpa);
    defer ctx.deinit();

    const items = &[_]Value{
        .{ .string = "x" },
        .{ .string = "y" },
    };
    try ctx.put("items", .{ .list = items });

    var tmpl = try Template.fromSource(gpa, "{% for item in items %}{{ forloop.first }}-{{ forloop.last }},{% endfor %}");
    defer tmpl.deinit();

    const output = try renderToSlice(gpa, &tmpl, &ctx);
    defer gpa.free(output);
    try std.testing.expectEqualStrings("true-false,false-true,", output);
}

test "renderer: {% include %} via TemplateEngine" {
    const gpa = std.testing.allocator;
    var engine = renderer.TemplateEngine.init(gpa);
    defer engine.deinit();

    _ = try engine.loadFromSource("header.html", "<header>Site Title</header>");
    _ = try engine.loadFromSource("page.html", "before{% include \"header.html\" %}after");

    var ctx = Context.init(gpa);
    defer ctx.deinit();

    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try engine.render("page.html", &ctx, &aw.writer);
    var buf = aw.toArrayList();
    const output = try buf.toOwnedSlice(gpa);
    defer gpa.free(output);

    try std.testing.expectEqualStrings("before<header>Site Title</header>after", output);
}

test "renderer: {% extends %} with block override via TemplateEngine" {
    const gpa = std.testing.allocator;
    var engine = renderer.TemplateEngine.init(gpa);
    defer engine.deinit();

    _ = try engine.loadFromSource("base.html", "<html>{% block content %}{% endblock %}</html>");
    _ = try engine.loadFromSource("child.html", "{% extends \"base.html\" %}{% block content %}<h1>Hello</h1>{% endblock %}");

    var ctx = Context.init(gpa);
    defer ctx.deinit();

    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try engine.render("child.html", &ctx, &aw.writer);
    var buf = aw.toArrayList();
    const output = try buf.toOwnedSlice(gpa);
    defer gpa.free(output);

    try std.testing.expectEqualStrings("<html><h1>Hello</h1></html>", output);
}

test "renderer: {% extends %} with context variables in blocks" {
    const gpa = std.testing.allocator;
    var engine = renderer.TemplateEngine.init(gpa);
    defer engine.deinit();

    _ = try engine.loadFromSource("base.html", "<div class=\"base\">{% block body %}{% endblock %}</div>");
    _ = try engine.loadFromSource("child.html", "{% extends \"base.html\" %}{% block body %}<p>{{ message }}</p>{% endblock %}");

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("message", .{ .string = "from context" });

    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try engine.render("child.html", &ctx, &aw.writer);
    var buf = aw.toArrayList();
    const output = try buf.toOwnedSlice(gpa);
    defer gpa.free(output);

    try std.testing.expectEqualStrings("<div class=\"base\"><p>from context</p></div>", output);
}

test "renderer: {% include %} with context values" {
    const gpa = std.testing.allocator;
    var engine = renderer.TemplateEngine.init(gpa);
    defer engine.deinit();

    _ = try engine.loadFromSource("greeting.html", "Hello {{ name }}!");
    _ = try engine.loadFromSource("page.html", "{% include \"greeting.html\" %} Welcome.");

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    try ctx.put("name", .{ .string = "Alice" });

    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    try engine.render("page.html", &ctx, &aw.writer);
    var buf = aw.toArrayList();
    const output = try buf.toOwnedSlice(gpa);
    defer gpa.free(output);

    try std.testing.expectEqualStrings("Hello Alice! Welcome.", output);
}
