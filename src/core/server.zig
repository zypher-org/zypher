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
    shutdown_requested: std.atomic.Value(bool) = .init(false),

    pub const Config = struct {
        host: []const u8 = "127.0.0.1",
        port: u16 = 8080,
        read_buffer_size: usize = 8192,
        write_buffer_size: usize = 8192,
        max_body_size: usize = 1_048_576, // 1 MiB
        /// Optional lifecycle bound used by tests and controlled shutdown flows.
        max_requests: ?usize = null,
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
            if (std.meta.stringToEnum(std.http.Method, method_str)) |std_method| {
                break :method Method.fromStdString(std_method);
            }
            log.warn("unknown HTTP method '{s}', returning 400", .{method_str});
            return error.BadRequest;
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
        var net_server = try std.Io.net.IpAddress.listen(&addr, io, .{});
        defer {
            if (!self.shutdown_requested.load(.acquire)) {
                net_server.deinit(io);
            }
        }
        self.listener = net_server;
        self.shutdown_requested.store(false, .release);

        log.info("listening on {s}:{d}", .{ self.config.host, self.config.port });

        var served_requests: usize = 0;
        while (!self.shutdown_requested.load(.acquire)) {
            const stream = net_server.accept(io) catch |err| {
                if (err == error.SocketNotListening and self.shutdown_requested.load(.acquire)) {
                    log.info("server shutdown requested", .{});
                    break;
                }
                log.warn("accept failed: {t}", .{err});
                continue;
            };
            self.handleConnection(io, gpa, stream, handler) catch |err| {
                log.warn("connection handler failed: {t}", .{err});
            };
            stream.close(io);
            served_requests += 1;
            if (self.config.max_requests) |max_requests| {
                if (served_requests >= max_requests) {
                    log.info("request limit reached ({d}), stopping server", .{max_requests});
                    break;
                }
            }
        }

        self.listener = null;
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

        var stream_reader = stream.reader(io, &read_buf);
        var stream_writer = stream.writer(io, &write_buf);

        var http_server = std.http.Server.init(&stream_reader.interface, &stream_writer.interface);

        while (true) {
            var server_req = http_server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                error.HttpHeadersOversize => {
                    log.warn("request headers too large", .{});
                    return;
                },
                error.HttpHeadersInvalid => {
                    log.warn("request headers invalid", .{});
                    return;
                },
                error.HttpRequestTruncated => {
                    log.warn("request truncated", .{});
                    return;
                },
                else => {
                    log.warn("request error: {t}", .{err});
                    return;
                },
            };

            var req = buildRequest(gpa, server_req.head_buffer, self.config.max_body_size) catch |err| {
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
            defer req.deinit();
            req.query_owned = true;

            // ── Read request body and parse supported form encodings ────
            if (server_req.head.method.requestHasBody()) {
                var body_read_buf: [4096]u8 = undefined;
                const body_reader = server_req.readerExpectNone(&body_read_buf);
                const body = std.Io.Reader.allocRemaining(body_reader, gpa, std.Io.Limit.limited(self.config.max_body_size)) catch |read_err| {
                    log.warn("body read failed: {t}", .{read_err});
                    return;
                };
                req.body = body;
                req.body_owned = true;

                if (body.len > 0) {
                    const content_type = Request.getHeaderCI(&req.headers, "content-type") orelse "";
                    if (std.mem.indexOf(u8, content_type, "x-www-form-urlencoded") != null) {
                        var form_params = Request.parseQueryString(gpa, body) catch {
                            log.warn("failed to parse form data", .{});
                            return;
                        };
                        defer form_params.deinit();
                        var iter = form_params.iterator();
                        while (iter.next()) |entry| {
                            req.query.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
                        }
                    } else if (std.mem.indexOf(u8, content_type, "multipart/form-data") != null) {
                        var multipart = Request.parseMultipartFormData(gpa, content_type, body) catch {
                            log.warn("failed to parse multipart form data", .{});
                            return;
                        };

                        var field_iter = multipart.fields.iterator();
                        while (field_iter.next()) |entry| {
                            if (try req.query.fetchPut(entry.key_ptr.*, entry.value_ptr.*)) |old| {
                                req.allocator.free(old.key);
                                if (old.value.len > 0) req.allocator.free(old.value);
                            }
                        }
                        multipart.fields.deinit();

                        req.files = multipart.files;
                        req.files_owned = true;
                    }
                }
            }

            log.info("{s} {s}", .{ @tagName(req.method), req.path });

            var res = Response.init(gpa);
            handler(&req, &res);
            defer res.deinit();

            var res_buf: std.ArrayList(u8) = .empty;
            defer res_buf.deinit(gpa);
            try res.send(gpa, &res_buf);
            try stream_writer.interface.writeAll(res_buf.items);
            try stream_writer.interface.flush();
        }
    }

    /// Graceful shutdown placeholder.
    pub fn shutdown(self: *Server, io: std.Io) void {
        self.shutdown_requested.store(true, .release);
        if (self.listener) |*l| {
            l.deinit(io);
            self.listener = null;
        }
    }
};
