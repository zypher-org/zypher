/// zypher App — top-level entry point that wires Server, handler, and config.
const std = @import("std");
const Server = @import("server.zig").Server;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const log = std.log.scoped(.app);

pub const App = struct {
    server: Server,
    allocator: std.mem.Allocator,
    handler_fn: ?Server.HandlerFn = null,
    /// When set, this handler takes priority over handler_fn.
    /// Use with Router.dispatch as the handler for routed apps.
    router_handler: ?Server.HandlerFn = null,

    /// Create a new App with the given allocator and optional config overrides.
    pub fn init(gpa: std.mem.Allocator, config: Server.Config) App {
        return .{
            .server = Server.init(config),
            .allocator = gpa,
        };
    }

    /// Free all owned resources.
    pub fn deinit(self: *App) void {
        _ = self;
    }

    /// Register a request handler function.
    pub fn handler(self: *App, fn_ptr: Server.HandlerFn) void {
        self.handler_fn = fn_ptr;
    }

    /// Register a router-based handler (takes priority over plain handler).
    pub fn routerHandler(self: *App, fn_ptr: Server.HandlerFn) void {
        self.router_handler = fn_ptr;
    }

    /// Build a zypher Request from a raw HTTP head buffer.
    pub fn buildRequestFromHead(self: *App, head_buffer: []const u8) !Request {
        return Server.buildRequest(self.allocator, head_buffer, self.server.config.max_body_size);
    }

    /// Dispatch a request through the registered handler, or return 404.
    /// Priority: router_handler > handler_fn > default 404.
    pub fn handleRequest(self: *App, req: *Request, res: *Response) void {
        if (self.router_handler) |h| {
            h(req, res);
            return;
        }
        if (self.handler_fn) |h| {
            h(req, res);
        } else {
            _ = res.status(404);
            res.text("Not Found") catch {};
            log.warn("no handler registered, returning 404 for {s} {s}", .{ @tagName(req.method), req.path });
        }
    }

    /// Start the server and begin accepting connections. Blocks until shutdown.
    pub fn listenAndServe(self: *App, io: std.Io) !void {
        if (self.router_handler == null and self.handler_fn == null) {
            log.warn("no handler registered — server will return 404 for all requests", .{});
        }
        const h = self.router_handler orelse self.handler_fn orelse defaultHandler;
        try self.server.listenAndServe(io, self.allocator, h);
    }

    /// Graceful shutdown.
    pub fn shutdown(self: *App, io: std.Io) void {
        self.server.shutdown(io);
    }

    /// Default handler that returns 404.
    fn defaultHandler(req: *Request, res: *Response) void {
        _ = req;
        _ = res.status(404);
        res.text("Not Found") catch {};
    }
};
