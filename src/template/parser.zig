/// zypher template parser — converts lexer tokens into an AST.
const std = @import("std");
const ArrayList = std.ArrayList;
const lexer = @import("lexer.zig");

const log = std.log.scoped(.template_parser);

pub const NodeType = enum {
    text,
    variable,
    if_block,
    for_block,
    block, // {% block name %}...{% endblock %}
    extends_, // {% extends "base.html" %}
    include, // {% include "partial.html" %}
};

pub const ElifBranch = struct {
    condition: []const u8,
    children: ArrayList(Node),
};

pub const Node = struct {
    type: NodeType,
    value: []const u8, // variable name, condition, iterable name, block name, template path
    loop_var: []const u8 = "", // for-block iterator variable name
    children: ArrayList(Node) = undefined, // body nodes
    else_children: ArrayList(Node) = undefined, // else branch nodes
    elif_branches: ArrayList(ElifBranch) = undefined, // elif branches

    pub fn init(t: NodeType, v: []const u8) Node {
        return .{
            .type = t,
            .value = v,
            .children = ArrayList(Node).empty,
            .else_children = ArrayList(Node).empty,
            .elif_branches = ArrayList(ElifBranch).empty,
        };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        for (self.children.items) |*child| child.deinit(allocator);
        self.children.deinit(allocator);
        for (self.else_children.items) |*child| child.deinit(allocator);
        self.else_children.deinit(allocator);
        for (self.elif_branches.items) |*branch| {
            for (branch.children.items) |*child| child.deinit(allocator);
            branch.children.deinit(allocator);
        }
        self.elif_branches.deinit(allocator);
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    pos: usize,
    nodes: ArrayList(Node),

    pub fn init(allocator: std.mem.Allocator, tokens: []const lexer.Token) Parser {
        return .{
            .allocator = allocator,
            .tokens = tokens,
            .pos = 0,
            .nodes = ArrayList(Node).empty,
        };
    }

    pub fn deinit(self: *Parser) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
    }

    const ParseError = error{
        UnclosedBlock,
        UnknownTag,
        InvalidForSyntax,
        InvalidExtendsSyntax,
        InvalidIncludeSyntax,
        OutOfMemory,
    };

    pub fn parse(self: *Parser) !void {
        try self.parseNodes(&self.nodes, null);
        log.debug("parsed {d} top-level nodes", .{self.nodes.items.len});
    }

    fn parseNodes(self: *Parser, list: *ArrayList(Node), end_tag: ?[]const u8) ParseError!void {
        while (self.pos < self.tokens.len) {
            const token = self.tokens[self.pos];

            // Check for end tag
            if (token.type == .tag) {
                if (end_tag) |etag| {
                    if (std.mem.eql(u8, token.value, etag) or
                        std.mem.startsWith(u8, token.value, etag))
                    {
                        return; // don't consume — caller handles
                    }
                }
                // Check for elif / else as end-of-branch signals
                if (std.mem.startsWith(u8, token.value, "elif ") or
                    std.mem.eql(u8, token.value, "else"))
                {
                    return;
                }
            }

            switch (token.type) {
                .text => {
                    try list.append(self.allocator, Node.init(.text, token.value));
                    self.pos += 1;
                },
                .variable => {
                    try list.append(self.allocator, Node.init(.variable, token.value));
                    self.pos += 1;
                },
                .tag => {
                    try self.parseTag(list);
                },
            }
        }
        // If we expected an end tag, it was never found
        if (end_tag != null) return error.UnclosedBlock;
    }

    fn parseTag(self: *Parser, list: *ArrayList(Node)) ParseError!void {
        const token = self.tokens[self.pos];
        const content = token.value;

        if (std.mem.startsWith(u8, content, "if ")) {
            try self.parseIf(list);
        } else if (std.mem.startsWith(u8, content, "for ")) {
            try self.parseFor(list);
        } else if (std.mem.startsWith(u8, content, "block ")) {
            try self.parseBlock(list);
        } else if (std.mem.startsWith(u8, content, "extends ")) {
            try self.parseExtends(list);
        } else if (std.mem.startsWith(u8, content, "include ")) {
            try self.parseInclude(list);
        } else {
            return error.UnknownTag;
        }
    }

    fn parseIf(self: *Parser, list: *ArrayList(Node)) ParseError!void {
        const content = self.tokens[self.pos].value;
        const condition = std.mem.trim(u8, content[3..], " \t"); // skip "if "

        var node = Node.init(.if_block, condition);
        self.pos += 1; // consume if tag

        // Parse true branch
        self.parseNodes(&node.children, "endif") catch |err| {
            node.deinit(self.allocator);
            return err;
        };

        // Handle elif / else / endif
        while (self.pos < self.tokens.len and self.tokens[self.pos].type == .tag) {
            const tag_val = self.tokens[self.pos].value;
            if (std.mem.startsWith(u8, tag_val, "elif ")) {
                const elif_cond = std.mem.trim(u8, tag_val[5..], " \t");
                self.pos += 1; // consume elif tag
                var branch = ElifBranch{
                    .condition = elif_cond,
                    .children = ArrayList(Node).empty,
                };
                try self.parseNodes(&branch.children, "endif");
                try node.elif_branches.append(self.allocator, branch);
            } else if (std.mem.eql(u8, tag_val, "else")) {
                self.pos += 1; // consume else tag
                try self.parseNodes(&node.else_children, "endif");
            } else if (std.mem.eql(u8, tag_val, "endif")) {
                self.pos += 1; // consume endif tag
                break;
            } else {
                break;
            }
        }

        try list.append(self.allocator, node);
    }

    fn parseFor(self: *Parser, list: *ArrayList(Node)) ParseError!void {
        const content = self.tokens[self.pos].value;
        // "for item in items"
        const rest = std.mem.trim(u8, content[4..], " \t"); // skip "for "
        const in_pos = std.mem.indexOf(u8, rest, " in ") orelse return error.InvalidForSyntax;
        const loop_var = std.mem.trim(u8, rest[0..in_pos], " \t");
        const iterable = std.mem.trim(u8, rest[in_pos + 4 ..], " \t");

        var node = Node.init(.for_block, iterable);
        node.loop_var = loop_var;
        self.pos += 1; // consume for tag

        self.parseNodes(&node.children, "endfor") catch |err| {
            node.deinit(self.allocator);
            return err;
        };

        // consume endfor
        if (self.pos < self.tokens.len and
            self.tokens[self.pos].type == .tag and
            std.mem.eql(u8, self.tokens[self.pos].value, "endfor"))
        {
            self.pos += 1;
        }

        try list.append(self.allocator, node);
    }

    fn parseBlock(self: *Parser, list: *ArrayList(Node)) ParseError!void {
        const content = self.tokens[self.pos].value;
        const block_name = std.mem.trim(u8, content[6..], " \t"); // skip "block "

        var node = Node.init(.block, block_name);
        self.pos += 1; // consume block tag

        self.parseNodes(&node.children, "endblock") catch |err| {
            node.deinit(self.allocator);
            return err;
        };

        // consume endblock
        if (self.pos < self.tokens.len and
            self.tokens[self.pos].type == .tag and
            std.mem.eql(u8, self.tokens[self.pos].value, "endblock"))
        {
            self.pos += 1;
        }

        try list.append(self.allocator, node);
    }

    fn parseExtends(self: *Parser, list: *ArrayList(Node)) ParseError!void {
        const content = self.tokens[self.pos].value;
        // "extends \"base.html\""
        const path = extractQuoted(content[8..]) orelse return error.InvalidExtendsSyntax;
        try list.append(self.allocator, Node.init(.extends_, path));
        self.pos += 1;
    }

    fn parseInclude(self: *Parser, list: *ArrayList(Node)) ParseError!void {
        const content = self.tokens[self.pos].value;
        // "include \"header.html\""
        const path = extractQuoted(content[8..]) orelse return error.InvalidIncludeSyntax;
        try list.append(self.allocator, Node.init(.include, path));
        self.pos += 1;
    }

    /// Extract a quoted string value from tag content (e.g. `"base.html"` → `base.html`).
    fn extractQuoted(s: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, s, " \t");
        if (trimmed.len < 2) return null;
        if (trimmed[0] != '"' and trimmed[0] != '\'') return null;
        const quote = trimmed[0];
        const end = std.mem.indexOfScalar(u8, trimmed[1..], quote) orelse return null;
        return trimmed[1 .. end + 1];
    }
};

test {
    std.testing.refAllDecls(@This());
}
