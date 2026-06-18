/// zypher Rate Limiter middleware — fixed window counter per IP.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.rate_limit);

/// Configuration for rate limiter.
pub const Config = struct {
    /// Maximum requests per window.
    max_requests: u32 = 100,
    /// Window duration in seconds.
    window_seconds: u32 = 60,
};

/// Per-IP rate limit state. Fixed window counter.
/// For v1, we use a simple HashMap with string keys.
/// Thread safety is not needed — v1 has no async.
pub const RateLimiter = struct {
    const Self = @This();
    const Entry = struct {
        count: u32,
        window_start: i64,
    };

    entries: std.StringHashMap(Entry),
    allocator: std.mem.Allocator,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return .{
            .entries = std.StringHashMap(Entry).init(allocator),
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all allocated key strings
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }

    /// Check if a request from the given key is allowed.
    /// Returns true if allowed, false if rate limited.
    pub fn allow(self: *Self, key: []const u8, io: std.Io) !bool {
        const now: i64 = @intCast(@divTrunc(std.Io.Timestamp.now(io, .real).nanoseconds, std.time.ns_per_s));

        if (self.entries.getPtr(key)) |entry| {
            // Check if window has expired
            if (now - entry.window_start >= self.config.window_seconds) {
                // Reset window
                entry.count = 1;
                entry.window_start = now;
                return true;
            }
            // Within window
            if (entry.count >= self.config.max_requests) {
                return false;
            }
            entry.count += 1;
            return true;
        }

        // New entry
        const owned_key = try self.allocator.dupe(u8, key);
        try self.entries.put(owned_key, .{ .count = 1, .window_start = now });
        return true;
    }
};

/// Global rate limiter instance for the default middleware.
var default_limiter: ?RateLimiter = null;

/// Default rate limit middleware (100 req/min).
pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    const DefaultRL = middlewareWith(.{ .max_requests = 100, .window_seconds = 60 });
    DefaultRL.handle(io, req, res, next);
}

/// Create a rate limit middleware with custom configuration.
/// Uses a comptime-known config to generate a typed middleware function.
/// Call `deinit(allocator)` after use to free internal state.
pub fn middlewareWith(comptime config: Config) type {
    return struct {
        var limiter: RateLimiter = undefined;
        var initialized: bool = false;

        pub fn handle(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
            if (!initialized) {
                limiter = RateLimiter.init(std.heap.page_allocator, config);
                initialized = true;
            }

            // Use remote IP from headers or fallback to "default"
            const ip = req.headers.get("X-Forwarded-For") orelse "default";

            const allowed = limiter.allow(ip, io) catch true;
            if (!allowed) {
                log.warn("rate limited: {s} on {s} {s}", .{ ip, @tagName(req.method), req.path });
                _ = res.status(429);
                _ = res.header("Retry-After", "60");
                res.text("Too Many Requests") catch {};
                return;
            }

            next(io, req, res);
        }

        /// Free internal state. Call after all requests are processed.
        pub fn deinit() void {
            if (initialized) {
                limiter.deinit();
                initialized = false;
            }
        }

        /// Get the middleware function pointer for use in Chain.
        pub fn middleware() *const fn (std.Io, *Request, *Response, *const fn (std.Io, *Request, *Response) void) void {
            return handle;
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}
