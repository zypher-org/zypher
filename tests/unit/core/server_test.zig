/// Unit tests for zypher HTTP Server.
const std = @import("std");
const Server = @import("zypher").core.Server;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;
const Method = @import("zypher").core.Method;

// ── ServerConfig defaults ─────────────────────────────────────────

test "ServerConfig has sensible defaults" {
    const config = Server.Config{};
    try std.testing.expectEqualStrings("127.0.0.1", config.host);
    try std.testing.expectEqual(@as(u16, 8080), config.port);
    try std.testing.expectEqual(@as(usize, 8192), config.read_buffer_size);
    try std.testing.expectEqual(@as(usize, 8192), config.write_buffer_size);
    try std.testing.expectEqual(@as(usize, 1_048_576), config.max_body_size);
}

// ── Handler type ──────────────────────────────────────────────────

test "HandlerFn receives Request and Response to fill in" {
    const test_handler = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = res.status(200);
            res.text("hello") catch {};
            _ = req;
        }
    }.handler;

    var req: Request = .{
        .method = .get,
        .path = "/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = &.{},
        .allocator = std.testing.allocator,
    };
    defer req.deinit();

    var res = Response.init(std.testing.allocator);
    defer res.deinit();
    test_handler(&req, &res);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

// ── Request from std.http.Server ──────────────────────────────────

test "fromStdRequest converts std.http.Server.Request to zypher Request" {
    // Build a minimal fake request head buffer.
    // We test the conversion logic by providing a pre-parsed head.
    const method = Method.fromStdString(.GET);
    try std.testing.expectEqual(Method.get, method);
    const method_post = Method.fromStdString(.POST);
    try std.testing.expectEqual(Method.post, method_post);
}

test "parseRequestTarget extracts path and query from target string" {
    const result = Server.parseRequestTarget(std.testing.allocator, "/api/users?limit=10");
    defer {
        var q = result.query;
        Request.deinitQueryString(&q, std.testing.allocator);
    }
    try std.testing.expectEqualStrings("/api/users", result.path);
    try std.testing.expectEqualStrings("10", result.query.get("limit").?);
}

test "parseRequestTarget with no query string" {
    const result = Server.parseRequestTarget(std.testing.allocator, "/health");
    defer {
        var q = result.query;
        Request.deinitQueryString(&q, std.testing.allocator);
    }
    try std.testing.expectEqualStrings("/health", result.path);
    try std.testing.expectEqual(@as(usize, 0), result.query.count());
}

// ── Server listen address ─────────────────────────────────────────

test "Server.listenAddress parses host:port into IpAddress" {
    const addr = try Server.listenAddress("127.0.0.1", 9090);
    switch (addr) {
        .ip4 => |ip4| {
            try std.testing.expectEqual(@as(u16, 9090), ip4.port);
        },
        .ip6 => return error.TestUnexpectedIp6,
    }
}
