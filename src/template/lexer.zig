/// zypher template lexer — tokenises template source into text, variable, tag, and comment tokens.
const std = @import("std");
const ArrayList = std.ArrayList;

const log = std.log.scoped(.template_lexer);

pub const TokenType = enum {
    text,
    variable, // {{ ... }}
    tag, // {% ... %}
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,

    pub fn init(t: TokenType, v: []const u8) Token {
        return .{ .type = t, .value = v };
    }
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,
    tokens: ArrayList(Token),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .tokens = ArrayList(Token).empty,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *Lexer) !void {
        while (self.pos < self.source.len) {
            if (self.match("{{")) {
                try self.scanVariable();
            } else if (self.match("{%")) {
                try self.scanTag();
            } else if (self.match("{#")) {
                try self.scanComment();
            } else {
                try self.scanText();
            }
        }
        log.debug("tokenised {d} tokens from {d} byte source", .{ self.tokens.items.len, self.source.len });
    }

    fn match(self: *Lexer, expected: []const u8) bool {
        if (self.pos + expected.len > self.source.len) return false;
        return std.mem.eql(u8, self.source[self.pos .. self.pos + expected.len], expected);
    }

    fn scanVariable(self: *Lexer) !void {
        self.pos += 2; // skip {{
        const end = std.mem.indexOfPos(u8, self.source, self.pos, "}}") orelse
            return error.UnclosedTag;
        const content = std.mem.trim(u8, self.source[self.pos..end], " \t\n\r");
        try self.tokens.append(self.allocator, Token.init(.variable, content));
        self.pos = end + 2;
    }

    fn scanTag(self: *Lexer) !void {
        self.pos += 2; // skip {%
        const end = std.mem.indexOfPos(u8, self.source, self.pos, "%}") orelse
            return error.UnclosedTag;
        const content = std.mem.trim(u8, self.source[self.pos..end], " \t\n\r");
        try self.tokens.append(self.allocator, Token.init(.tag, content));
        self.pos = end + 2;
    }

    fn scanComment(self: *Lexer) !void {
        self.pos += 2; // skip {#
        const end = std.mem.indexOfPos(u8, self.source, self.pos, "#}") orelse
            return error.UnclosedTag;
        // Comments are stripped — no token emitted
        self.pos = end + 2;
    }

    fn scanText(self: *Lexer) !void {
        const start = self.pos;
        while (self.pos < self.source.len) {
            if (self.match("{{") or self.match("{%") or self.match("{#")) break;
            self.pos += 1;
        }
        if (self.pos > start) {
            try self.tokens.append(self.allocator, Token.init(.text, self.source[start..self.pos]));
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}
