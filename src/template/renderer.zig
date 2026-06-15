/// zypher template renderer — renders parsed template AST with context values.
/// Auto-escapes HTML by default; use |safe filter to bypass.
/// Supports {{ var.field }}, {{ list.0 }}, {% include %}, {% extends %}.
const std = @import("std");
const ArrayList = std.ArrayList;
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const log = std.log.scoped(.template_renderer);

pub const Value = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
    list: []const Value,
    map: *Context,
    null_val: void,

    pub fn format(self: Value, writer: *std.Io.Writer) error{ OutOfMemory, WriteFailed }!void {
        switch (self) {
            .string => |s| try writer.writeAll(s),
            .int => |n| try writer.print("{d}", .{n}),
            .float => |f| try writer.print("{d:.2}", .{f}),
            .bool => |b| try writer.writeAll(if (b) "true" else "false"),
            .list => |items| {
                for (items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(writer);
                }
            },
            .map => |m| {
                var it = m.data.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll(": ");
                    try entry.value_ptr.*.format(writer);
                }
            },
            .null_val => {},
        }
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .string => |s| s.len > 0,
            .int => |n| n != 0,
            .float => |f| f != 0.0,
            .bool => |b| b,
            .list => |items| items.len > 0,
            .map => true,
            .null_val => false,
        };
    }
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .data = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.data.deinit();
    }

    pub fn put(self: *Context, key: []const u8, value: Value) !void {
        try self.data.put(key, value);
    }

    pub fn get(self: *Context, key: []const u8) ?Value {
        return self.data.get(key);
    }
};

pub const Template = struct {
    allocator: std.mem.Allocator,
    nodes: ArrayList(parser.Node),
    source: []const u8,
    engine: ?*anyopaque = null,

    pub fn fromSource(allocator: std.mem.Allocator, source: []const u8) !Template {
        var lx = lexer.Lexer.init(allocator, source);
        try lx.tokenize();
        var p = parser.Parser.init(allocator, lx.tokens.items);
        try p.parse();

        // Take ownership of parser's nodes — avoid shallow copy
        const owned_nodes = p.nodes;
        p.nodes = ArrayList(parser.Node).empty; // prevent double-free
        p.deinit();
        lx.deinit();

        log.debug("parsed template from {d} byte source into {d} nodes", .{ source.len, owned_nodes.items.len });
        return .{
            .allocator = allocator,
            .nodes = owned_nodes,
            .source = source,
        };
    }

    pub fn deinit(self: *Template) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
    }

    const RenderError = error{ OutOfMemory, WriteFailed };

    pub fn render(self: *Template, ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        // Handle {% extends %} as the first node
        if (self.nodes.items.len > 0 and self.nodes.items[0].type == .extends_) {
            if (self.engine) |eng| {
                const engine: *TemplateEngine = @ptrCast(@alignCast(eng));
                return self.renderExtended(engine, ctx, writer);
            } else {
                log.warn("extends ignored — no engine: {s}", .{self.nodes.items[0].value});
            }
        }
        for (self.nodes.items) |node| {
            try self.renderNode(node, ctx, writer);
        }
    }

    fn renderNode(self: *Template, node: parser.Node, ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        switch (node.type) {
            .text => try writer.writeAll(node.value),
            .variable => try self.renderVariable(node.value, ctx, writer),
            .if_block => try self.renderIf(node, ctx, writer),
            .for_block => try self.renderFor(node, ctx, writer),
            .block => {
                for (node.children.items) |child| {
                    try self.renderNode(child, ctx, writer);
                }
            },
            .extends_ => {},
            .include => {
                if (self.engine) |eng| {
                    const engine: *TemplateEngine = @ptrCast(@alignCast(eng));
                    const included = engine.getTemplate(node.value) orelse {
                        log.warn("template not found: {s}", .{node.value});
                        return;
                    };
                    try included.render(ctx, writer);
                } else {
                    log.warn("include ignored — no engine: {s}", .{node.value});
                }
            },
        }
    }

    fn resolveVar(ctx: *Context, expr: []const u8) Value {
        var dot_parts = std.mem.splitSequence(u8, expr, ".");
        var current: Value = undefined;
        var first = true;
        while (dot_parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (first) {
                current = ctx.get(trimmed) orelse Value.null_val;
                first = false;
            } else {
                switch (current) {
                    .map => |m| {
                        current = m.get(trimmed) orelse Value.null_val;
                    },
                    .list => |items| {
                        const idx = std.fmt.parseInt(usize, trimmed, 10) catch return Value.null_val;
                        if (idx < items.len) current = items[idx] else current = Value.null_val;
                    },
                    else => current = Value.null_val,
                }
            }
        }
        return current;
    }

    fn renderVariable(self: *Template, expr: []const u8, ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        const f = @import("filters.zig");
        var parts = std.mem.splitScalar(u8, expr, '|');
        const var_expr = std.mem.trim(u8, parts.first(), " \t");
        var current = resolveVar(ctx, var_expr);
        var current_owned = false;

        var is_safe = false;
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");

            if (std.mem.eql(u8, trimmed, "safe")) {
                is_safe = true;
                continue;
            }

            const result = if (std.mem.indexOfScalar(u8, trimmed, '(')) |paren| blk: {
                const fname = std.mem.trim(u8, trimmed[0..paren], " \t");
                const rest = std.mem.trim(u8, trimmed[paren + 1 ..], " \t");
                const arg = if (rest.len > 0 and rest[rest.len - 1] == ')') rest[0 .. rest.len - 1] else "";
                break :blk f.applyWithArg(self.allocator, fname, current, arg) catch {
                    log.warn("filter with arg failed", .{});
                    if (current_owned) {
                        var tmp = f.FilterResult{ .value = current, .owned = true };
                        tmp.deinit(self.allocator);
                    }
                    return;
                };
            } else f.apply(self.allocator, trimmed, current) catch {
                log.warn("filter failed", .{});
                if (current_owned) {
                    var tmp = f.FilterResult{ .value = current, .owned = true };
                    tmp.deinit(self.allocator);
                }
                return;
            };

            if (current_owned) {
                var tmp = f.FilterResult{ .value = current, .owned = true };
                tmp.deinit(self.allocator);
            }
            current = result.value;
            current_owned = result.owned;
        }

        if (is_safe) {
            try current.format(writer);
        } else {
            try htmlEscape(current, writer);
        }

        if (current_owned) {
            var tmp = f.FilterResult{ .value = current, .owned = true };
            tmp.deinit(self.allocator);
        }
    }

    fn htmlEscape(value: Value, writer: *std.Io.Writer) RenderError!void {
        switch (value) {
            .string => |s| {
                for (s) |c| {
                    switch (c) {
                        '<' => try writer.writeAll("&lt;"),
                        '>' => try writer.writeAll("&gt;"),
                        '&' => try writer.writeAll("&amp;"),
                        '"' => try writer.writeAll("&quot;"),
                        '\'' => try writer.writeAll("&#x27;"),
                        else => try writer.writeAll(&.{c}),
                    }
                }
            },
            else => try value.format(writer),
        }
    }

    fn renderIf(self: *Template, node: parser.Node, ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        const value = ctx.get(node.value) orelse Value.null_val;

        if (value.isTruthy()) {
            for (node.children.items) |child| try self.renderNode(child, ctx, writer);
        } else {
            var handled = false;
            for (node.elif_branches.items) |branch| {
                const elif_val = ctx.get(branch.condition) orelse Value.null_val;
                if (elif_val.isTruthy()) {
                    for (branch.children.items) |child| try self.renderNode(child, ctx, writer);
                    handled = true;
                    break;
                }
            }
            if (!handled) {
                for (node.else_children.items) |child| try self.renderNode(child, ctx, writer);
            }
        }
    }

    fn renderFor(self: *Template, node: parser.Node, ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        const iterable = ctx.get(node.value) orelse return;
        switch (iterable) {
            .list => |items| {
                var child_ctx = Context.init(self.allocator);
                defer child_ctx.deinit();

                var it = ctx.data.iterator();
                while (it.next()) |entry| {
                    try child_ctx.data.put(entry.key_ptr.*, entry.value_ptr.*);
                }

                var forloop_ctx = Context.init(self.allocator);
                defer forloop_ctx.deinit();

                for (items, 0..) |item, i| {
                    try child_ctx.data.put(node.loop_var, item);
                    try forloop_ctx.data.put("counter0", .{ .int = @as(i64, @intCast(i)) });
                    try forloop_ctx.data.put("counter", .{ .int = @as(i64, @intCast(i + 1)) });
                    try forloop_ctx.data.put("first", .{ .bool = i == 0 });
                    try forloop_ctx.data.put("last", .{ .bool = i == items.len - 1 });
                    try child_ctx.data.put("forloop", .{ .map = &forloop_ctx });

                    for (node.children.items) |child| {
                        try self.renderNode(child, &child_ctx, writer);
                    }
                }
            },
            else => log.warn("for iterable '{s}' is not a list", .{node.value}),
        }
    }
    fn renderExtended(self: *Template, engine: *TemplateEngine, ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        const base_name = self.nodes.items[0].value;
        const base_tmpl = engine.getTemplate(base_name) orelse {
            log.warn("base template not found: {s}", .{base_name});
            return;
        };

        var blocks = std.StringHashMap([]const parser.Node).init(self.allocator);
        defer blocks.deinit();
        for (self.nodes.items[1..]) |child_node| {
            if (child_node.type == .block) {
                try blocks.put(child_node.value, child_node.children.items);
            }
        }

        try self.renderWithBlocks(base_tmpl, &blocks, ctx, writer);
    }

    fn renderWithBlocks(self: *Template, tmpl: *Template, blocks: *std.StringHashMap([]const parser.Node), ctx: *Context, writer: *std.Io.Writer) RenderError!void {
        _ = self;
        for (tmpl.nodes.items) |node| {
            if (node.type == .block) {
                if (blocks.get(node.value)) |child_children| {
                    for (child_children) |child_node| {
                        try tmpl.renderNode(child_node, ctx, writer);
                    }
                } else {
                    for (node.children.items) |child_node| {
                        try tmpl.renderNode(child_node, ctx, writer);
                    }
                }
            } else {
                try tmpl.renderNode(node, ctx, writer);
            }
        }
    }
};

pub const TemplateEngine = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(Template),

    pub fn init(allocator: std.mem.Allocator) TemplateEngine {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(Template).init(allocator),
        };
    }

    pub fn deinit(self: *TemplateEngine) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            var tmpl = entry.value_ptr.*;
            tmpl.deinit();
        }
        self.cache.deinit();
    }

    pub fn getTemplate(self: *TemplateEngine, name: []const u8) ?*Template {
        return self.cache.getPtr(name);
    }

    pub fn load(self: *TemplateEngine, name: []const u8, source: []const u8) !*Template {
        if (self.cache.getPtr(name)) |tmpl| {
            log.debug("cache hit for template '{s}'", .{name});
            return tmpl;
        }
        var tmpl = try Template.fromSource(self.allocator, source);
        tmpl.engine = @ptrCast(self);
        try self.cache.put(name, tmpl);
        log.debug("loaded and cached template '{s}'", .{name});
        return self.cache.getPtr(name).?;
    }

    pub fn render(self: *TemplateEngine, name: []const u8, ctx: *Context, writer: *std.Io.Writer) !void {
        const tmpl = self.cache.get(name) orelse return error.TemplateNotFound;
        var mut_tmpl = tmpl;
        try mut_tmpl.render(ctx, writer);
    }
};

test {
    std.testing.refAllDecls(@This());
}
