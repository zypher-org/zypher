/// zypher App — top-level entry point that wires Server, handler, and config.
const std = @import("std");
const Server = @import("server.zig").Server;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const sqlite = @import("../orm/sqlite.zig");
const orm_config = @import("../orm/config.zig");
const driver_iface = @import("../orm/driver/interface.zig");
const doc_iface = @import("../orm/document/interface.zig");
const kv_iface = @import("../orm/kv/interface.zig");
const log = std.log.scoped(.app);

pub const App = struct {
    server: Server,
    allocator: std.mem.Allocator,
    handler_fn: ?Server.HandlerFn = null,
    router_handler: ?Server.HandlerFn = null,
    middleware_handler: ?Server.HandlerFn = null,
    /// Legacy database connection (via *sqlite.Db).
    _legacy_db: ?*sqlite.Db = null,
    /// Owned open-db handle (for lifecycle).
    _open_db: ?orm_config.OpenDb = null,
    /// Cached vtable references extracted from _open_db.
    _relational_db: ?driver_iface.RelationalDb = null,
    _document_store: ?doc_iface.DocumentStore = null,
    _kv_store: ?kv_iface.KVStore = null,

    pub fn init(gpa: std.mem.Allocator, server_config: Server.Config) App {
        return .{
            .server = Server.init(server_config),
            .allocator = gpa,
        };
    }

    /// Free all owned resources.
    pub fn deinit(self: *App) void {
        if (self._legacy_db) |legacy| {
            legacy.close();
        }
        if (self._open_db) |*odb| {
            odb.close(self.allocator);
        }
    }

    pub fn handler(self: *App, fn_ptr: Server.HandlerFn) void {
        self.handler_fn = fn_ptr;
    }

    pub fn routerHandler(self: *App, fn_ptr: Server.HandlerFn) void {
        self.router_handler = fn_ptr;
    }

    /// Legacy: attach a pre-opened sqlite database.
    pub fn database(self: *App, handle: *sqlite.Db) void {
        self._legacy_db = handle;
    }

    /// Open and attach a database via the config API. Owns the connection.
    /// Extracts the appropriate vtable wrapper from the open result.
    pub fn useDatabase(self: *App, gpa: std.mem.Allocator, cfg: orm_config.DatabaseConfig) (orm_config.ConfigError || std.mem.Allocator.Error)!void {
        const result = try orm_config.openDatabase(gpa, cfg);
        self._open_db = result.open_db;
        self._relational_db = result.relational;
        self._document_store = result.document;
        self._kv_store = result.kv;
    }

    /// Return the relational database handle, or an error.
    pub fn db(self: *App) orm_config.ConfigError!driver_iface.RelationalDb {
        if (self._relational_db) |d| return d;
        if (self._open_db != null) return error.WrongStoreType;
        return error.NoDatabaseConfigured;
    }

    /// Return the document store handle, or an error.
    pub fn documentStore(self: *App) orm_config.ConfigError!doc_iface.DocumentStore {
        if (self._document_store) |s| return s;
        if (self._open_db != null) return error.WrongStoreType;
        return error.NoDatabaseConfigured;
    }

    /// Return the KV store handle, or an error.
    pub fn kvStore(self: *App) orm_config.ConfigError!kv_iface.KVStore {
        if (self._kv_store) |s| return s;
        if (self._open_db != null) return error.WrongStoreType;
        return error.NoDatabaseConfigured;
    }

    /// Register a middleware handler (takes priority over router and handler).
    /// The middleware handler is a Server.HandlerFn that typically wraps
    /// a Chain.run() call with the router/handler as the terminal handler.
    pub fn middlewareHandler(self: *App, fn_ptr: Server.HandlerFn) void {
        self.middleware_handler = fn_ptr;
    }

    /// Build a zypher Request from a raw HTTP head buffer.
    pub fn buildRequestFromHead(self: *App, head_buffer: []const u8) !Request {
        return Server.buildRequest(self.allocator, head_buffer, self.server.config.max_body_size);
    }

    /// Dispatch a request through the registered handlers.
    /// Priority: middleware_handler > router_handler > handler_fn > default 404.
    pub fn handleRequest(self: *App, req: *Request, res: *Response) void {
        if (self.middleware_handler) |h| {
            h(req, res);
            return;
        }
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
        if (self.middleware_handler == null and self.router_handler == null and self.handler_fn == null) {
            log.warn("no handler registered — server will return 404 for all requests", .{});
        }
        const h = self.middleware_handler orelse self.router_handler orelse self.handler_fn orelse defaultHandler;
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
