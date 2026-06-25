const std = @import("std");
const zypher = @import("zypher");
const domain = @import("../domain/note.zig");

const Context = zypher.template.renderer.Context;
const TemplateEngine = zypher.template.renderer.TemplateEngine;
const Response = zypher.core.Response;

pub fn loadTemplates(engine: *TemplateEngine) !void {
    _ = try engine.loadFromSource("layout.html", @embedFile("templates/layout.html"));
    _ = try engine.loadFromSource("login.html", @embedFile("templates/login.html"));
    _ = try engine.loadFromSource("form.html", @embedFile("templates/form.html"));
}

pub fn render(engine: *TemplateEngine, res: *Response, name: []const u8, ctx: *Context) void {
    var aw = std.Io.Writer.Allocating.init(res.allocator);
    defer aw.deinit();
    engine.render(name, ctx, &aw.writer) catch {
        _ = res.status(500);
        res.text("Template render failed") catch {};
        return;
    };
    res.html(aw.written()) catch {
        _ = res.status(500);
    };
}

pub fn htmlEscape(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (value) |c| {
        switch (c) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            '"' => try out.appendSlice(allocator, "&quot;"),
            '\'' => try out.appendSlice(allocator, "&#x27;"),
            else => try out.append(allocator, c),
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn noteCards(allocator: std.mem.Allocator, rows: []const domain.NoteRow, csrf_field: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    if (rows.len == 0) {
        try out.appendSlice(allocator, "<section class=\"empty\"><h2>No notes yet</h2><p>Create your first note to start capturing ideas.</p></section>");
        return out.toOwnedSlice(allocator);
    }

    for (rows) |row| {
        const title = try htmlEscape(allocator, row[1]);
        defer allocator.free(title);
        const body = try htmlEscape(allocator, row[2]);
        defer allocator.free(body);
        const tags = try htmlEscape(allocator, row[3]);
        defer allocator.free(tags);

        try out.appendSlice(allocator, "<article class=\"note-card\">");
        try out.print(allocator, "<header><h2><a href=\"/notes/{d}\">{s}</a></h2>", .{ row[0], title });
        if (row[4]) try out.appendSlice(allocator, "<span class=\"pin\">Pinned</span>");
        try out.appendSlice(allocator, "</header>");
        try out.print(allocator, "<p>{s}</p>", .{body});
        if (tags.len > 0) try out.print(allocator, "<div class=\"tags\">{s}</div>", .{tags});
        try out.appendSlice(allocator, "<footer>");
        try out.print(allocator, "<a href=\"/notes/{d}/edit\">Edit</a>", .{row[0]});
        if (row[5]) {
            try out.print(allocator, "<form method=\"post\" action=\"/notes/{d}/restore\">{s}<button>Restore</button></form>", .{ row[0], csrf_field });
        } else {
            try out.print(allocator, "<form method=\"post\" action=\"/notes/{d}/archive\">{s}<button>Archive</button></form>", .{ row[0], csrf_field });
        }
        try out.print(allocator, "<form method=\"post\" action=\"/notes/{d}/delete\">{s}<button class=\"danger\">Delete</button></form>", .{ row[0], csrf_field });
        try out.appendSlice(allocator, "</footer></article>");
    }

    return out.toOwnedSlice(allocator);
}

pub fn noteView(allocator: std.mem.Allocator, row: domain.NoteRow, csrf_field: []const u8) ![]u8 {
    const title = try htmlEscape(allocator, row[1]);
    defer allocator.free(title);
    const body = try htmlEscape(allocator, row[2]);
    defer allocator.free(body);
    const tags = try htmlEscape(allocator, row[3]);
    defer allocator.free(tags);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "<article class=\"note-view\">");
    try out.appendSlice(allocator, "<header class=\"toolbar\"><div>");
    try out.print(allocator, "<h1>{s}</h1>", .{title});
    if (tags.len > 0) try out.print(allocator, "<p class=\"tags\">{s}</p>", .{tags});
    try out.appendSlice(allocator, "</div><div class=\"actions\">");
    try out.print(allocator, "<a class=\"button\" href=\"/notes/{d}/edit\">Edit</a>", .{row[0]});
    if (row[5]) {
        try out.print(allocator, "<form method=\"post\" action=\"/notes/{d}/restore\">{s}<button>Restore</button></form>", .{ row[0], csrf_field });
    } else {
        try out.print(allocator, "<form method=\"post\" action=\"/notes/{d}/archive\">{s}<button>Archive</button></form>", .{ row[0], csrf_field });
    }
    try out.print(allocator, "<form method=\"post\" action=\"/notes/{d}/delete\">{s}<button class=\"danger\">Delete</button></form>", .{ row[0], csrf_field });
    try out.appendSlice(allocator, "</div></header>");
    if (row[4]) try out.appendSlice(allocator, "<span class=\"pin\">Pinned</span>");
    try out.print(allocator, "<p class=\"note-body\">{s}</p>", .{body});
    try out.appendSlice(allocator, "</article>");

    return out.toOwnedSlice(allocator);
}
