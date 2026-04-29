const std = @import("std");
const parser = @import("zypher").template.parser;
const lexer = @import("zypher").template.lexer;

const Node = parser.Node;
const NodeType = parser.NodeType;
const Parser = parser.Parser;
const Lexer = lexer.Lexer;

const ParseResult = struct {
    lx: Lexer,
    p: Parser,
    pub fn deinit(self: *ParseResult) void {
        self.p.deinit();
        self.lx.deinit();
    }
};

fn parseSrc(gpa: std.mem.Allocator, src: []const u8) !ParseResult {
    var lx = Lexer.init(gpa, src);
    errdefer lx.deinit();
    try lx.tokenize();
    var p = Parser.init(gpa, lx.tokens.items);
    errdefer p.deinit();
    try p.parse();
    return .{ .lx = lx, .p = p };
}

test "parser: parse variable expression" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "{{ name }}");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(NodeType.variable, nodes[0].type);
    try std.testing.expectEqualStrings("name", nodes[0].value);
}

test "parser: parse plain text" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "hello world");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(NodeType.text, nodes[0].type);
    try std.testing.expectEqualStrings("hello world", nodes[0].value);
}

test "parser: parse if / else / endif" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "{% if active %}yes{% else %}no{% endif %}");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(NodeType.if_block, nodes[0].type);
    try std.testing.expectEqualStrings("active", nodes[0].value);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].children.items.len);
    try std.testing.expectEqual(NodeType.text, nodes[0].children.items[0].type);
    try std.testing.expectEqualStrings("yes", nodes[0].children.items[0].value);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].else_children.items.len);
    try std.testing.expectEqual(NodeType.text, nodes[0].else_children.items[0].type);
    try std.testing.expectEqualStrings("no", nodes[0].else_children.items[0].value);
}

test "parser: parse if / elif / else / endif" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "{% if a %}A{% elif b %}B{% else %}C{% endif %}");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(NodeType.if_block, nodes[0].type);
    try std.testing.expectEqualStrings("a", nodes[0].value);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].elif_branches.items.len);
    try std.testing.expectEqualStrings("b", nodes[0].elif_branches.items[0].condition);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].elif_branches.items[0].children.items.len);
    try std.testing.expectEqual(NodeType.text, nodes[0].elif_branches.items[0].children.items[0].type);
    try std.testing.expectEqualStrings("B", nodes[0].elif_branches.items[0].children.items[0].value);
}

test "parser: parse for item in list / endfor" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "{% for item in items %}{{ item }}{% endfor %}");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(NodeType.for_block, nodes[0].type);
    try std.testing.expectEqualStrings("item", nodes[0].loop_var);
    try std.testing.expectEqualStrings("items", nodes[0].value);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].children.items.len);
    try std.testing.expectEqual(NodeType.variable, nodes[0].children.items[0].type);
    try std.testing.expectEqualStrings("item", nodes[0].children.items[0].value);
}

test "parser: parse extends and block" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "{% extends \"base.html\" %}{% block title %}My Title{% endblock %}");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 2), nodes.len);
    try std.testing.expectEqual(NodeType.extends_, nodes[0].type);
    try std.testing.expectEqualStrings("base.html", nodes[0].value);
    try std.testing.expectEqual(NodeType.block, nodes[1].type);
    try std.testing.expectEqualStrings("title", nodes[1].value);
    try std.testing.expectEqual(@as(usize, 1), nodes[1].children.items.len);
    try std.testing.expectEqual(NodeType.text, nodes[1].children.items[0].type);
    try std.testing.expectEqualStrings("My Title", nodes[1].children.items[0].value);
}

test "parser: parse include" {
    const gpa = std.testing.allocator;
    var r = try parseSrc(gpa, "{% include \"header.html\" %}");
    defer r.deinit();
    const nodes = r.p.nodes.items;
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqual(NodeType.include, nodes[0].type);
    try std.testing.expectEqualStrings("header.html", nodes[0].value);
}

test "parser: error on unknown tag" {
    const gpa = std.testing.allocator;
    const result = parseSrc(gpa, "{% unknown_tag %}");
    try std.testing.expectError(error.UnknownTag, result);
}

test "parser: error on unclosed if block" {
    const gpa = std.testing.allocator;
    const result = parseSrc(gpa, "{% if active %}yes");
    try std.testing.expectError(error.UnclosedBlock, result);
}

test "parser: error on unclosed for block" {
    const gpa = std.testing.allocator;
    const result = parseSrc(gpa, "{% for item in items %}{{ item }}");
    try std.testing.expectError(error.UnclosedBlock, result);
}
