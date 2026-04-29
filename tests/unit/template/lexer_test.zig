const std = @import("std");
const lexer = @import("zypher").template.lexer;

const Token = lexer.Token;
const TokenType = lexer.TokenType;
const Lexer = lexer.Lexer;

test "lexer: tokenise plain text" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "hello world");
    defer lx.deinit();
    try lx.tokenize();

    const tokens = lx.tokens.items;
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("hello world", tokens[0].value);
}

test "lexer: tokenise variable expression {{ variable }}" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "{{ name }}");
    defer lx.deinit();
    try lx.tokenize();

    const tokens = lx.tokens.items;
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenType.variable, tokens[0].type);
    try std.testing.expectEqualStrings("name", tokens[0].value);
}

test "lexer: tokenise tag block {% tag %}" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "{% if active %}");
    defer lx.deinit();
    try lx.tokenize();

    const tokens = lx.tokens.items;
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenType.tag, tokens[0].type);
    try std.testing.expectEqualStrings("if active", tokens[0].value);
}

test "lexer: tokenise comment {# comment #} stripped from output" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "before{# ignored #}after");
    defer lx.deinit();
    try lx.tokenize();

    const tokens = lx.tokens.items;
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("before", tokens[0].value);
    try std.testing.expectEqual(TokenType.text, tokens[1].type);
    try std.testing.expectEqualStrings("after", tokens[1].value);
}

test "lexer: tokenise mixed content" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "Hello {{ name }}! {% if show %}visible{% endif %}");
    defer lx.deinit();
    try lx.tokenize();

    const tokens = lx.tokens.items;
    try std.testing.expectEqual(@as(usize, 6), tokens.len);

    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("Hello ", tokens[0].value);

    try std.testing.expectEqual(TokenType.variable, tokens[1].type);
    try std.testing.expectEqualStrings("name", tokens[1].value);

    try std.testing.expectEqual(TokenType.text, tokens[2].type);
    try std.testing.expectEqualStrings("! ", tokens[2].value);

    try std.testing.expectEqual(TokenType.tag, tokens[3].type);
    try std.testing.expectEqualStrings("if show", tokens[3].value);

    try std.testing.expectEqual(TokenType.text, tokens[4].type);
    try std.testing.expectEqualStrings("visible", tokens[4].value);

    try std.testing.expectEqual(TokenType.tag, tokens[5].type);
    try std.testing.expectEqualStrings("endif", tokens[5].value);
}

test "lexer: reject unclosed variable tag" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "{{ unclosed");
    defer lx.deinit();
    const result = lx.tokenize();
    try std.testing.expectError(error.UnclosedTag, result);
}

test "lexer: reject unclosed block tag" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "{% unclosed");
    defer lx.deinit();
    const result = lx.tokenize();
    try std.testing.expectError(error.UnclosedTag, result);
}

test "lexer: reject unclosed comment" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "{# unclosed");
    defer lx.deinit();
    const result = lx.tokenize();
    try std.testing.expectError(error.UnclosedTag, result);
}

test "lexer: tokenise variable with filter {{ name | upper }}" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "{{ name | upper }}");
    defer lx.deinit();
    try lx.tokenize();

    const tokens = lx.tokens.items;
    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenType.variable, tokens[0].type);
    try std.testing.expectEqualStrings("name | upper", tokens[0].value);
}

test "lexer: empty input produces no tokens" {
    const gpa = std.testing.allocator;
    var lx = Lexer.init(gpa, "");
    defer lx.deinit();
    try lx.tokenize();

    try std.testing.expectEqual(@as(usize, 0), lx.tokens.items.len);
}
