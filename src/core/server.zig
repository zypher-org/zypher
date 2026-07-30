/// zypher HTTP Server — binds, accepts, parses, and dispatches.
const std = @import("std");
const Method = @import("method.zig").Method;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const IoBackend = @import("io_backend.zig").IoBackend;
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
        max_body_size: usize = 10_485_760, // 10 MiB
        /// Bodies larger than this are not buffered — the handler reads them
        /// via `Request.body_stream`. Set to `max_body_size` to inline all bodies.
        max_inline_body_size: usize = 1_048_576, // 1 MiB
        /// Optional lifecycle bound used by tests and controlled shutdown flows.
        max_requests: ?usize = null,
        /// IO backend selection.
        io_backend: IoBackend = .threaded,
        /// Thread count for threaded backend (null = auto-detect via CPU count).
        thread_count: ?u32 = null,
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

        var parsed_target = parseRequestTarget(gpa, target);
        errdefer {
            Request.deinitQueryString(&parsed_target.query, gpa);
        }

        // Parse headers
        var headers = std.StringHashMap([]const u8).init(gpa);
        errdefer headers.deinit();
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
    /// Under a threaded backend, each connection is spawned via io.concurrent()
    /// for true parallelism. Under single-threaded, falls back to sequential
    /// inline serving (no panic, no error propagation to caller).
    ///
    /// The caller-supplied Io is never stored by the framework (Axiom A1).
    pub fn listenAndServe(self: *Server, io: std.Io, gpa: std.mem.Allocator, handler: HandlerFn) !void {
        const addr = try listenAddress(self.config.host, self.config.port);
        var net_server = try std.Io.net.IpAddress.listen(&addr, io, .{});
        defer net_server.deinit(io);
        self.listener = net_server;
        self.shutdown_requested.store(false, .release);

        log.info("listening on {s}:{d} (io={s})", .{ self.config.host, self.config.port, @typeName(@TypeOf(io)) });

        var futures_array: std.ArrayList(std.Io.Future(void)) = .empty;
        defer {
            for (futures_array.items) |*f| {
                f.await(io);
            }
            futures_array.deinit(gpa);
        }

        var served_requests: usize = 0;

        while (!self.shutdown_requested.load(.acquire)) {
            io.checkCancel() catch |check_err| switch (check_err) {
                error.Canceled => {
                    log.info("server io cancelled, shutting down", .{});
                    break;
                },
            };
            const stream = net_server.accept(io) catch |err| {
                if (self.shutdown_requested.load(.acquire) or err == error.SocketNotListening) {
                    log.info("server shutdown requested", .{});
                    break;
                }
                if (err == error.Canceled) {
                    log.info("server accept cancelled", .{});
                    break;
                }
                log.warn("accept failed: {t}", .{err});
                continue;
            };
            served_requests += 1;

            var future = io.concurrent(handleConnection, .{
                io,
                stream,
                gpa,
                handler,
                self.config.max_body_size,
                self.config.max_inline_body_size,
            }) catch |concurrent_err| switch (concurrent_err) {
                error.ConcurrencyUnavailable => {
                    log.warn("concurrent spawn unavailable — serving inline (single-threaded mode)", .{});
                    handleConnection(io, stream, gpa, handler, self.config.max_body_size, self.config.max_inline_body_size);
                    // skip future tracking — handled inline
                    continue;
                },
                else => |e| return e,
            };
            futures_array.append(gpa, future) catch |e| {
                future.cancel(io);
                return e;
            };

            if (self.config.max_requests) |max_requests| {
                if (served_requests >= max_requests) {
                    log.info("request limit reached ({d}), stopping server", .{max_requests});
                    break;
                }
            }
        }

        self.listener = null;
    }

    /// Handle a single HTTP request on a connection. Returns after one
    /// request-response cycle (one-shot). Signature compatible with io.concurrent/Future.
    fn handleConnection(
        io: std.Io,
        stream: std.Io.net.Stream,
        gpa: std.mem.Allocator,
        handler: HandlerFn,
        max_body_size: usize,
        max_inline_body_size: usize,
    ) void {
        defer stream.close(io);

        var read_buf: [8192]u8 = undefined;
        var write_buf: [8192]u8 = undefined;

        var stream_reader = stream.reader(io, &read_buf);
        var stream_writer = stream.writer(io, &write_buf);

        var http_server = std.http.Server.init(&stream_reader.interface, &stream_writer.interface);

        io.checkCancel() catch {
            log.info("connection handler cancelled", .{});
            return;
        };
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

        var req = buildRequest(gpa, server_req.head_buffer, max_body_size) catch |err| {
            log.warn("failed to build request: {t}", .{err});
            var err_res = Response.init(gpa);
            defer err_res.deinit();
            _ = err_res.status(400);
            err_res.text("Bad Request") catch {};
            err_res.send(io, &stream_writer.interface) catch {};
            stream_writer.interface.flush() catch {};
            return;
        };
        defer req.deinit();
        req.query_owned = true;

        // ── Read request body or leave as stream ────
        var body_read_buf: [4096]u8 = undefined;
        var body_reader: ?*std.Io.Reader = null;
        var body_stream_active = false;

        if (server_req.head.method.requestHasBody()) {
            body_reader = server_req.readerExpectNone(&body_read_buf);
            const br = body_reader.?;

            // If Content-Length exceeds inline threshold, stream instead of buffering
            const is_streaming = stream: {
                const cl_str = Request.getHeaderCI(&req.headers, "content-length") orelse break :stream false;
                const cl = std.fmt.parseInt(usize, cl_str, 10) catch break :stream false;
                break :stream cl > max_inline_body_size;
            };

            if (is_streaming) {
                req.body_stream = Request.BodyStream{ .reader = body_reader.? };
                body_stream_active = true;
            } else {
                const body = br.allocRemaining(gpa, std.Io.Limit.limited(max_body_size)) catch |read_err| {
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
                            if (req.query.fetchPut(entry.key_ptr.*, entry.value_ptr.*)) |maybe_old| {
                                if (maybe_old) |old| {
                                    req.allocator.free(old.key);
                                    if (old.value.len > 0) req.allocator.free(old.value);
                                }
                            } else |_| {}
                        }
                        multipart.fields.deinit();

                        req.files = multipart.files;
                        req.files_owned = true;
                    }
                }
            }
        }

        log.info("{s} {s}", .{ @tagName(req.method), req.path });

        var res = Response.init(gpa);
        handler(&req, &res);
        defer res.deinit();

        // Drain unconsumed streaming body before sending response
        if (body_stream_active) {
            if (req.body_stream) |*bs| {
                bs.skip() catch |err| {
                    log.warn("failed to drain body: {t}", .{err});
                };
            }
        }

        res.send(io, &stream_writer.interface) catch {
            log.warn("response send failed", .{});
            return;
        };
        stream_writer.interface.flush() catch {
            log.warn("response flush failed", .{});
            return;
        };
    }

    /// Graceful shutdown — sets the shutdown flag and makes a self-connection
    /// to unblock any in-progress accept(). The listener is left open until
    /// listenAndServe() exits (its defer block handles final cleanup).
    ///
    /// We self-connect rather than close() the listener to avoid triggering
    /// zig's EBADF assertion (the threaded IO backend treats closing an fd
    /// that another thread is blocked on as a programmer bug).
    /// In-flight connections drain naturally as clients close their streams.
    pub fn shutdown(self: *Server, io: std.Io) void {
        self.shutdown_requested.store(true, .release);
        if (self.listener != null) {
            const addr = listenAddress(self.config.host, self.config.port) catch return;
            // Make a connection to our own address so the blocking accept()
            // in the server thread returns and the loop can observe the flag.
            if (std.Io.net.IpAddress.connect(&addr, io, .{ .mode = .stream })) |conn| {
                conn.close(io);
            } else |_| {}
        }
    }
};
