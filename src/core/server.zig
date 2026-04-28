/// zypher HTTP Server — binds, accepts, parses, and dispatches.
const std = @import("std");
const Method = @import("method.zig").Method;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const log = std.log.scoped(.server);

pub const Server = struct {
    /// Handler function type: receives a Request and a Response to fill in.
    pub const HandlerFn = *const fn (*Request, *Response) void;

    config: Config,
    listener: ?std.Io.net.Server = null,

    pub const Config = struct {
        host: []const u8 = "127.0.0.1",
        port: u16 = 8080,
        read_buffer_size: usize = 8192,
        write_buffer_size: usize = 8192,
        max_body_size: usize = 1_048_576, // 1 MiB
    };

    /// Create a Server with the given configuration.
    pub fn init(config: Config) Server {
        return .{ .config = config };
    }

    /// Parse host + port into an IpAddress suitable for listen().
    pub fn listenAddress(host: []const u8, port: u16) !std.Io.net.IpAddress {
        return .{ .ip4 = try std.Io.net.Ip4Address.parse(host, port) };
    }

    /// Result of parsing a request target (path + query).
    pub const ParsedTarget = struct {
        path: []const u8,
        query: std.StringHashMap([]const u8),
    };

    /// Parse a request target string into path and query components.
    pub fn parseRequestTarget(gpa: std.mem.Allocator, target: []const u8) ParsedTarget {
        const path = Request.parsePath(target);
        const query_start = if (std.mem.indexOfScalar(u8, target, '?')) |i| i + 1 else target.len;
        const query_str = if (query_start < target.len) target[query_start..] else "";
        const query = Request.parseQueryString(gpa, query_str) catch
            std.StringHashMap([]const u8).init(gpa);
        return .{
            .path = path,
            .query = query,
        };
    }

    /// Build a zypher Request from a std.http.Server head buffer.
    /// The head buffer is the raw bytes from receiveHead().
    pub fn buildRequest(
        gpa: std.mem.Allocator,
        head_buffer: []const u8,
        max_body_size: usize,
    ) !Request {
        // Parse the first line: METHOD TARGET HTTP/1.x
        var line_it = std.mem.splitSequence(u8, head_buffer, "\r\n");
        const request_line = line_it.next() orelse return error.BadRequest;

        // Split request line into method, target, version
        var parts = std.mem.splitSequence(u8, request_line, " ");
        const method_str = parts.next() orelse return error.BadRequest;
        const target = parts.next() orelse return error.BadRequest;
        _ = parts.next() orelse return error.BadRequest; // version

        const method: Method = method: {
            // Try to match against std.http.Method strings
            inline for (@typeInfo(std.http.Method).@"enum".fields) |field| {
                if (std.mem.eql(u8, method_str, field.name)) {
                    break :method Method.fromStdString(@enumFromInt(field.value));
                }
            }
            break :method .get;
        };

        const parsed_target = parseRequestTarget(gpa, target);

        // Parse headers
        var headers = std.StringHashMap([]const u8).init(gpa);
        while (line_it.next()) |line| {
            if (line.len == 0) break;
            if (std.mem.indexOfScalar(u8, line, ':')) |i| {
                const name = line[0..i];
                var value = line[i + 1 ..];
                // Trim leading whitespace from header value
                value = std.mem.trimStart(u8, value, " \t");
                try headers.put(name, value);
            }
        }

        // Check content-length for body size validation
        if (Request.getHeaderCI(&headers, "content-length")) |cl_str| {
            const body_len = std.fmt.parseInt(usize, cl_str, 10) catch 0;
            try Request.validateBodySize(body_len, max_body_size);
        }

        return Request{
            .method = method,
            .path = parsed_target.path,
            .query = parsed_target.query,
            .headers = headers,
            .body = &.{},
            .allocator = gpa,
        };
    }

    /// Start listening and serving requests. Blocks until shutdown.
    pub fn listenAndServe(self: *Server, io: std.Io, gpa: std.mem.Allocator, handler: HandlerFn) !void {
        const addr = try listenAddress(self.config.host, self.config.port);
        var net_server = try std.Io.net.listen(&addr, io, .{});
        defer net_server.deinit(io);
        self.listener = net_server;

        log.info("listening on {s}:{d}", .{ self.config.host, self.config.port });

        while (true) {
            const stream = net_server.accept(io) catch |err| {
                log.warn("accept failed: {t}", .{err});
                continue;
            };
            self.handleConnection(io, gpa, stream, handler) catch |err| {
                log.warn("connection handler failed: {t}", .{err});
            };
            stream.close(io);
        }
    }

    /// Handle a single HTTP connection.
    fn handleConnection(
        self: *Server,
        io: std.Io,
        gpa: std.mem.Allocator,
        stream: std.Io.net.Stream,
        handler: HandlerFn,
    ) !void {
        var read_buf: [8192]u8 = undefined;
        var write_buf: [8192]u8 = undefined;

        const stream_reader = stream.reader(io, &read_buf);
        const stream_writer = stream.writer(io, &write_buf);

        var http_server = std.http.Server.init(&stream_reader.interface, &stream_writer.interface);

        while (true) {
            const head_buffer = http_server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                error.HttpHeadersOversize => {
                    log.warn("request headers too large", .{});
                    return;
                },
                error.HttpRequestTruncated => {
                    log.warn("request truncated", .{});
                    return;
                },
                error.ReadFailed => {
                    log.warn("read failed on connection", .{});
                    return;
                },
            };

            var req = buildRequest(gpa, head_buffer, self.config.max_body_size) catch |err| {
                log.warn("failed to build request: {t}", .{err});
                var err_res = Response.init(gpa);
                errdefer err_res.deinit();
                _ = err_res.status(400);
                try err_res.text("Bad Request");
                var res_buf: std.ArrayList(u8) = .empty;
                defer res_buf.deinit(gpa);
                try err_res.send(gpa, &res_buf);
                try stream_writer.interface.writeAll(res_buf.items);
                try stream_writer.interface.flush();
                err_res.deinit();
                continue;
            };

            log.info("{s} {s}", .{ @tagName(req.method), req.path });

            var res = Response.init(gpa);
            handler(&req, &res);
            defer res.deinit();

            var res_buf: std.ArrayList(u8) = .empty;
            defer res_buf.deinit(gpa);
            try res.send(gpa, &res_buf);
            try stream_writer.interface.writeAll(res_buf.items);
            try stream_writer.interface.flush();

            req.deinit();
        }
    }

    /// Graceful shutdown placeholder.
    pub fn shutdown(self: *Server, io: std.Io) void {
        if (self.listener) |*l| {
            l.deinit(io);
            self.listener = null;
        }
    }
};
