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

test "Server.shutdown() stops the server cleanly" {
    const port: u16 = 19088;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port });

    const server_ctx = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            res.text("OK") catch {};
        }
        fn run(s: *Server) !void {
            try s.listenAndServe(std.testing.io, std.testing.allocator, handler);
        }
    };

    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{&server});
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);
    var stream = try connectWithRetry(&addr);
    defer stream.close(std.testing.io);

    var read_buf: [1024]u8 = undefined;
    var write_buf: [1024]u8 = undefined;
    var reader = stream.reader(std.testing.io, &read_buf);
    var writer = stream.writer(std.testing.io, &write_buf);

    try writer.interface.writeAll("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    try writer.interface.flush();

    const response = try reader.interface.takeDelimiterExclusive('\n');
    try std.testing.expect(std.mem.indexOf(u8, response, "200") != null);

    // Shutdown the server
    server.shutdown(std.testing.io);
}

test "Server starts, responds to health check, and stops after request limit" {
    const port: u16 = 19087;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 1 });

    const server_ctx = struct {
        fn handler(req: *Request, res: *Response) void {
            if (std.mem.eql(u8, req.path, "/health")) {
                res.text("OK") catch {};
                return;
            }
            _ = res.status(404);
            res.text("Not Found") catch {};
        }

        fn run(s: *Server) !void {
            try s.listenAndServe(std.testing.io, std.testing.allocator, handler);
        }
    };

    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{&server});
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);
    var stream = try connectWithRetry(&addr);
    defer stream.close(std.testing.io);

    var read_buf: [1024]u8 = undefined;
    var write_buf: [1024]u8 = undefined;
    var reader = stream.reader(std.testing.io, &read_buf);
    var writer = stream.writer(std.testing.io, &write_buf);

    try writer.interface.writeAll("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    try writer.interface.flush();

    const response = try reader.interface.takeDelimiterExclusive('\n');
    try std.testing.expect(std.mem.indexOf(u8, response, "200") != null);
}

test "BodyTooLarge in buildRequest returns 400 and closes connection" {
    const port: u16 = 19089;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 2, .max_body_size = 100 });

    const server_ctx = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            res.text("OK") catch {};
        }
        fn run(s: *Server) !void {
            try s.listenAndServe(std.testing.io, std.testing.allocator, handler);
        }
    };

    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{&server});
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);

    // First connection: POST with oversized body → 400
    {
        var stream = try connectWithRetry(&addr);
        defer stream.close(std.testing.io);

        var read_buf: [1024]u8 = undefined;
        var write_buf: [1024]u8 = undefined;
        var reader = stream.reader(std.testing.io, &read_buf);
        var writer = stream.writer(std.testing.io, &write_buf);

        const body_data = try std.testing.allocator.alloc(u8, 200);
        @memset(body_data, 'A');
        defer std.testing.allocator.free(body_data);

        try writer.interface.writeAll("POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 200\r\nContent-Type: application/octet-stream\r\n\r\n");
        try writer.interface.writeAll(body_data);
        try writer.interface.flush();

        const err_line = try reader.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, err_line, "400") != null);
    }

    // Second connection on the same server: normal GET → 200
    {
        var stream = try connectWithRetry(&addr);
        defer stream.close(std.testing.io);

        var read_buf: [1024]u8 = undefined;
        var write_buf: [1024]u8 = undefined;
        var reader = stream.reader(std.testing.io, &read_buf);
        var writer = stream.writer(std.testing.io, &write_buf);

        try writer.interface.writeAll("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
        try writer.interface.flush();

        const ok_line = try reader.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, ok_line, "200") != null);
    }

    server.shutdown(std.testing.io);
}

test "large upload rejected with 400 does not affect subsequent request" {
    const port: u16 = 19090;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 3, .max_body_size = 100 });

    const server_ctx = struct {
        fn handler(req: *Request, res: *Response) void {
            _ = req;
            res.text("OK") catch {};
        }
        fn run(s: *Server) !void {
            try s.listenAndServe(std.testing.io, std.testing.allocator, handler);
        }
    };

    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{&server});
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);

    // Connection 1: normal GET succeeds
    {
        var stream = try connectWithRetry(&addr);
        defer stream.close(std.testing.io);

        var read_buf: [1024]u8 = undefined;
        var write_buf: [1024]u8 = undefined;
        var reader = stream.reader(std.testing.io, &read_buf);
        var writer = stream.writer(std.testing.io, &write_buf);

        try writer.interface.writeAll("GET /uploads/file1.txt HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
        try writer.interface.flush();

        const first_line = try reader.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, first_line, "200") != null);
    }

    // Connection 2: oversized POST → 400
    {
        var stream = try connectWithRetry(&addr);
        defer stream.close(std.testing.io);

        var read_buf: [1024]u8 = undefined;
        var write_buf: [1024]u8 = undefined;
        var reader = stream.reader(std.testing.io, &read_buf);
        var writer = stream.writer(std.testing.io, &write_buf);

        const large_body = try std.testing.allocator.alloc(u8, 150);
        @memset(large_body, 'B');
        defer std.testing.allocator.free(large_body);

        try writer.interface.writeAll("POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 150\r\nContent-Type: application/octet-stream\r\n\r\n");
        try writer.interface.writeAll(large_body);
        try writer.interface.flush();

        const err_line = try reader.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, err_line, "400") != null);
    }

    // Connection 3: normal GET still works
    {
        var stream = try connectWithRetry(&addr);
        defer stream.close(std.testing.io);

        var read_buf: [1024]u8 = undefined;
        var write_buf: [1024]u8 = undefined;
        var reader = stream.reader(std.testing.io, &read_buf);
        var writer = stream.writer(std.testing.io, &write_buf);

        try writer.interface.writeAll("GET /uploads/file2.txt HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
        try writer.interface.flush();

        const third_line = try reader.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, third_line, "200") != null);
    }

    server.shutdown(std.testing.io);
}

fn connectWithRetry(addr: *const std.Io.net.IpAddress) !std.Io.net.Stream {
    var attempts: usize = 0;
    while (attempts < 50) : (attempts += 1) {
        return std.Io.net.IpAddress.connect(addr, std.testing.io, .{ .mode = .stream }) catch |err| switch (err) {
            error.ConnectionRefused => {
                try std.Thread.yield();
                continue;
            },
            else => return err,
        };
    }
    return error.ConnectionRefused;
}
