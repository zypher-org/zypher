/// Unit tests for zypher Response.
const std = @import("std");
const Response = @import("zypher").core.Response;

// ── Status code and reason phrase ────────────────────────────────

test "Response.status sets status code and returns self for chaining" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    const ret = res.status(200);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expectEqualStrings("OK", res.reason_phrase.?);
    // Chaining: ret is *Response
    _ = ret;
}

test "Response.status with 404 sets reason phrase" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    _ = res.status(404);
    try std.testing.expectEqual(@as(u16, 404), res.status_code);
    try std.testing.expectEqualStrings("Not Found", res.reason_phrase.?);
}

test "Response.status with unknown code has no default phrase" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    _ = res.status(999);
    try std.testing.expectEqual(@as(u16, 999), res.status_code);
    try std.testing.expectEqual(@as(?[]const u8, null), res.reason_phrase);
}

// ── Response headers ─────────────────────────────────────────────

test "Response.header sets a header and returns self for chaining" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    _ = res.header("Content-Type", "text/html");
    _ = res.header("X-Custom", "value");
    try std.testing.expectEqualStrings("text/html", res.headers.get("Content-Type").?);
    try std.testing.expectEqualStrings("value", res.headers.get("X-Custom").?);
}

// ── Text body ────────────────────────────────────────────────────

test "Response.text sets body and content-type to text/plain" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    try res.text("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", res.body.?);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", res.headers.get("Content-Type").?);
}

// ── HTML body ────────────────────────────────────────────────────

test "Response.html sets body and content-type to text/html" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    try res.html("<h1>Welcome</h1>");
    try std.testing.expectEqualStrings("<h1>Welcome</h1>", res.body.?);
    try std.testing.expectEqualStrings("text/html; charset=utf-8", res.headers.get("Content-Type").?);
}

// ── JSON body ────────────────────────────────────────────────────

test "Response.json sets body and content-type to application/json" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    try res.json("{\"status\":\"ok\"}");
    try std.testing.expectEqualStrings("{\"status\":\"ok\"}", res.body.?);
    try std.testing.expectEqualStrings("application/json", res.headers.get("Content-Type").?);
}

// ── Redirect ─────────────────────────────────────────────────────

test "Response.redirect sets status and Location header" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    try res.redirect("/login", 302);
    try std.testing.expectEqual(@as(u16, 302), res.status_code);
    try std.testing.expectEqualStrings("/login", res.headers.get("Location").?);
}

test "Response.redirect with 301 permanent" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    try res.redirect("/new-home", 301);
    try std.testing.expectEqual(@as(u16, 301), res.status_code);
    try std.testing.expectEqualStrings("/new-home", res.headers.get("Location").?);
}

// ── Cookie ───────────────────────────────────────────────────────

test "Response.setCookie adds Set-Cookie header" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    _ = res.setCookie(.{
        .name = "session",
        .value = "abc123",
        .path = "/",
        .http_only = true,
        .secure = true,
        .same_site = .Strict,
    });
    const cookie_header = res.headers.get("Set-Cookie").?;
    try std.testing.expect(cookie_header.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, cookie_header, "session=abc123") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie_header, "HttpOnly") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie_header, "Secure") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie_header, "SameSite=Strict") != null);
}

test "Response.deleteCookie sets expired cookie" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    _ = res.deleteCookie("session");
    const cookie_header = res.headers.get("Set-Cookie").?;
    try std.testing.expect(std.mem.indexOf(u8, cookie_header, "session=") != null);
    try std.testing.expect(std.mem.indexOf(u8, cookie_header, "Max-Age=0") != null);
}

// ── Serialise response to bytes ──────────────────────────────────

test "Response.send serialises HTTP/1.1 response" {
    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    _ = res.status(200);
    try res.text("OK");
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try res.send(std.testing.allocator, &buf);
    const output = buf.items;
    // Should start with HTTP/1.1 200 OK
    try std.testing.expect(std.mem.startsWith(u8, output, "HTTP/1.1 200 OK\r\n"));
    // Should contain Content-Type
    try std.testing.expect(std.mem.indexOf(u8, output, "Content-Type: text/plain; charset=utf-8\r\n") != null);
    // Should end with body
    try std.testing.expect(std.mem.endsWith(u8, output, "OK"));
}

// ── Deinit ───────────────────────────────────────────────────────

test "Response.deinit frees all owned memory" {
    var res = Response.init(std.testing.allocator);
    _ = res.status(200);
    try res.text("Hello");
    _ = res.header("X-Test", "value");
    res.deinit();
}
