/// Unit tests for zypher Request parsing.
const std = @import("std");
const Request = @import("zypher").core.Request;
const Method = @import("zypher").core.Method;

// ── Method parsing ──────────────────────────────────────────────

test "parse method from HTTP request line — all standard methods" {
    const testing = std.testing;
    try testing.expectEqual(Method.get, Method.fromStdString(.GET));
    try testing.expectEqual(Method.post, Method.fromStdString(.POST));
    try testing.expectEqual(Method.put, Method.fromStdString(.PUT));
    try testing.expectEqual(Method.delete, Method.fromStdString(.DELETE));
    try testing.expectEqual(Method.patch, Method.fromStdString(.PATCH));
    try testing.expectEqual(Method.head, Method.fromStdString(.HEAD));
    try testing.expectEqual(Method.options, Method.fromStdString(.OPTIONS));
}

// ── Path and query string parsing ────────────────────────────────

test "parse path from request target — simple path" {
    const path = Request.parsePath("/users/42");
    try std.testing.expectEqualStrings("/users/42", path);
}

test "parse path from request target — with query string" {
    const path = Request.parsePath("/search?q=zig&lang=en");
    try std.testing.expectEqualStrings("/search", path);
}

test "parse query string from request target" {
    var query = try Request.parseQueryString(std.testing.allocator, "q=zig&lang=en");
    defer Request.deinitQueryString(&query, std.testing.allocator);
    try std.testing.expectEqualStrings("zig", query.get("q").?);
    try std.testing.expectEqualStrings("en", query.get("lang").?);
}

test "parse query string — empty query returns empty map" {
    var query = try Request.parseQueryString(std.testing.allocator, "");
    defer Request.deinitQueryString(&query, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), query.count());
}

test "parse query string — key with no value" {
    var query = try Request.parseQueryString(std.testing.allocator, "flag&name=test");
    defer Request.deinitQueryString(&query, std.testing.allocator);
    try std.testing.expectEqualStrings("", query.get("flag").?);
    try std.testing.expectEqualStrings("test", query.get("name").?);
}

// ── Header parsing ──────────────────────────────────────────────

test "header lookup is case-insensitive" {
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "text/html");
    try headers.put("x-request-id", "abc123");

    try std.testing.expectEqualStrings("text/html", Request.getHeaderCI(&headers, "content-type").?);
    try std.testing.expectEqualStrings("text/html", Request.getHeaderCI(&headers, "CONTENT-TYPE").?);
    try std.testing.expectEqualStrings("abc123", Request.getHeaderCI(&headers, "X-Request-Id").?);
    try std.testing.expectEqual(@as(?[]const u8, null), Request.getHeaderCI(&headers, "authorization"));
}

// ── Content-Type and Content-Length ──────────────────────────────

test "extract content type from headers" {
    var headers = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer headers.deinit();
    try headers.put("Content-Type", "application/json");
    try headers.put("Content-Length", "42");

    const ct = Request.getHeaderCI(&headers, "content-type");
    const cl = Request.getHeaderCI(&headers, "content-length");
    try std.testing.expectEqualStrings("application/json", ct.?);
    try std.testing.expectEqualStrings("42", cl.?);
}

// ── Body size enforcement ────────────────────────────────────────

test "reject body exceeding max_body_size" {
    const max: usize = 10;
    const body_len: usize = 100;
    try std.testing.expectError(error.BodyTooLarge, Request.validateBodySize(body_len, max));
}

test "accept body within max_body_size" {
    const max: usize = 1024;
    const body_len: usize = 512;
    try Request.validateBodySize(body_len, max);
}

// ── URL-encoded form body parsing ────────────────────────────────

test "parse application/x-www-form-urlencoded body" {
    var form = try Request.parseFormUrlEncoded(std.testing.allocator, "username=alice&password=s3cret");
    defer Request.deinitQueryString(&form, std.testing.allocator);
    try std.testing.expectEqualStrings("alice", form.get("username").?);
    try std.testing.expectEqualStrings("s3cret", form.get("password").?);
}

test "parse form body — URL-encoded special characters" {
    var form = try Request.parseFormUrlEncoded(std.testing.allocator, "name=hello+world&email=a%40b.com");
    defer Request.deinitQueryString(&form, std.testing.allocator);
    try std.testing.expectEqualStrings("hello world", form.get("name").?);
    try std.testing.expectEqualStrings("a@b.com", form.get("email").?);
}

// ── Cookie parsing ──────────────────────────────────────────────

test "parse cookies from Cookie header" {
    var cookies = try Request.parseCookies(std.testing.allocator, "session=abc123; theme=dark");
    defer cookies.deinit();
    try std.testing.expectEqualStrings("abc123", cookies.get("session").?);
    try std.testing.expectEqualStrings("dark", cookies.get("theme").?);
}

test "parse cookies — empty Cookie header" {
    var cookies = try Request.parseCookies(std.testing.allocator, "");
    defer cookies.deinit();
    try std.testing.expectEqual(@as(usize, 0), cookies.count());
}

// ── Request deinit ──────────────────────────────────────────────

test "Request.deinit frees all owned memory" {
    var req: Request = .{
        .method = .get,
        .path = "/test",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    try req.headers.put("Host", "localhost");
    try req.query.put("q", "test");
    req.deinit();
}
