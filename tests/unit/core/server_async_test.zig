const std = @import("std");
const zypher = @import("zypher");
const test_io = @import("test_io");
const Server = zypher.core.Server;
const Request = zypher.core.Request;
const Response = zypher.core.Response;

fn handlerOK(req: *Request, res: *Response) void {
    _ = req;
    res.text("OK") catch {};
}

test "multi-threaded: a single request on threaded backend succeeds" {
    // Same pattern as existing server_test.zig — uses std.testing.io
    // to verify Group.concurrent path doesn't break basic serving.
    const port: u16 = 19350;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 1 });

    const server_ctx = struct {
        fn run(s: *Server) !void {
            try s.listenAndServe(std.testing.io, std.testing.allocator, handlerOK);
        }
    };
    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{&server});
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);

    var conn = try connectWithRetry(&addr);
    defer conn.close(std.testing.io);

    var buf: [1024]u8 = undefined;
    var wbuf: [128]u8 = undefined;
    var r = conn.reader(std.testing.io, &buf);
    var w = conn.writer(std.testing.io, &wbuf);

    try w.interface.writeAll("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    try w.interface.flush();

    const resp = try r.interface.takeDelimiterExclusive('\n');
    try std.testing.expect(std.mem.indexOf(u8, resp, "200") != null);

    server.shutdown(std.testing.io);
}

test "single-threaded: falls back to sequential handling, no panic" {
    const port: u16 = 19351;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 2 });
    var single_backend = std.Io.Threaded.init_single_threaded;
    const server_io = single_backend.io();

    const server_ctx = struct {
        fn run(s: *Server, i: std.Io) !void {
            try s.listenAndServe(i, std.testing.allocator, handlerOK);
        }
    };
    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{ &server, server_io });
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);

    {
        var conn = try connectWithRetry(&addr);
        defer conn.close(std.testing.io);
        var buf: [1024]u8 = undefined;
        var wbuf: [128]u8 = undefined;
        var r = conn.reader(std.testing.io, &buf);
        var w = conn.writer(std.testing.io, &wbuf);
        try w.interface.writeAll("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
        try w.interface.flush();
        const resp = try r.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, resp, "200") != null);
    }
    {
        var conn = try connectWithRetry(&addr);
        defer conn.close(std.testing.io);
        var buf: [1024]u8 = undefined;
        var wbuf: [128]u8 = undefined;
        var r = conn.reader(std.testing.io, &buf);
        var w = conn.writer(std.testing.io, &wbuf);
        try w.interface.writeAll("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
        try w.interface.flush();
        const resp = try r.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, resp, "200") != null);
    }

    server.shutdown(server_io);
}

test "shutdown cancels in-flight futures, zero leaks" {
    const port: u16 = 19252;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 10 });
    const server_io = test_io.testIoThreaded();

    const server_ctx = struct {
        fn run(s: *Server, i: std.Io) !void {
            try s.listenAndServe(i, std.testing.allocator, handlerOK);
        }
    };
    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{ &server, server_io });
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);

    var conn = try connectWithRetry(&addr);
    var wbuf: [128]u8 = undefined;
    var w = conn.writer(std.testing.io, &wbuf);
    try w.interface.writeAll("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    try w.interface.flush();

    server.shutdown(server_io);
    conn.close(std.testing.io);
}

test "malformed connection does not cancel other in-flight tasks" {
    const port: u16 = 19353;
    var server = Server.init(.{ .host = "127.0.0.1", .port = port, .max_requests = 3 });
    const server_io = test_io.testIoThreaded();

    const server_ctx = struct {
        fn run(s: *Server, i: std.Io) !void {
            try s.listenAndServe(i, std.testing.allocator, handlerOK);
        }
    };
    var thread = try std.Thread.spawn(.{}, server_ctx.run, .{ &server, server_io });
    defer thread.join();

    const addr = try Server.listenAddress("127.0.0.1", port);

    {
        var conn = try connectWithRetry(&addr);
        defer conn.close(std.testing.io);
        var buf: [1024]u8 = undefined;
        var wbuf: [128]u8 = undefined;
        var w = conn.writer(std.testing.io, &wbuf);
        var r = conn.reader(std.testing.io, &buf);
        try w.interface.writeAll("GARBAGE NOT HTTP\r\n\r\n");
        try w.interface.flush();
        _ = r.interface.takeDelimiterExclusive('\n') catch {};
    }

    {
        var conn = try connectWithRetry(&addr);
        defer conn.close(std.testing.io);
        var buf: [1024]u8 = undefined;
        var wbuf: [128]u8 = undefined;
        var w = conn.writer(std.testing.io, &wbuf);
        var r = conn.reader(std.testing.io, &buf);
        try w.interface.writeAll("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
        try w.interface.flush();
        const resp = try r.interface.takeDelimiterExclusive('\n');
        try std.testing.expect(std.mem.indexOf(u8, resp, "200") != null);
    }

    server.shutdown(server_io);
}

fn connectWithRetry(addr: *const std.Io.net.IpAddress) !std.Io.net.Stream {
    var attempts: usize = 0;
    while (attempts < 50) : (attempts += 1) {
        return std.Io.net.IpAddress.connect(addr, std.testing.io, .{ .mode = .stream }) catch |err| switch (err) {
            error.ConnectionRefused => {
                std.Thread.yield() catch {};
                continue;
            },
            else => return err,
        };
    }
    return error.ConnectionRefused;
}
