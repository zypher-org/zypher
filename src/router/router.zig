/// zypher Router — comptime route table with runtime dispatch.
const std = @import("std");
const Method = @import("../core/method.zig").Method;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const Route = @import("route.zig").Route;
const RouteParams = @import("params.zig").RouteParams;
const log = std.log.scoped(.router);

pub const Router = struct {
    routes: []const Route,
    not_found_handler: *const fn (*Request, *Response) void,

    /// Create a route entry for use in a comptime routes tuple.
    pub fn route(m: Method, pattern: []const u8, handler: *const fn (*Request, *Response) void) Route {
        return Route.init(m, pattern, handler);
    }

    /// Initialise the router with a comptime tuple of routes and a 404 handler.
    pub fn init(comptime routes: anytype, not_found: *const fn (*Request, *Response) void) Router {
        // Validate all patterns at comptime
        const route_list = comptime blk: {
            const fields = std.meta.fields(@TypeOf(routes));
            var list: [fields.len]Route = undefined;
            for (fields, 0..) |field, i| {
                const r = @field(routes, field.name);
                Route.validatePattern(r.pattern) catch |err| {
                    @compileError("Invalid route pattern '" ++ r.pattern ++ "': " ++ @errorName(err));
                };
                list[i] = r;
            }
            break :blk list;
        };

        return .{
            .routes = &route_list,
            .not_found_handler = not_found,
        };
    }

    /// Dispatch a request to the matching route handler.
    /// - Path match + method match → handler
    /// - Path match + method mismatch → 405 with Allow header
    /// - No path match → 404
    pub fn dispatch(self: *const Router, req: *Request, res: *Response) void {
        var params = RouteParams.init(req.allocator);
        defer params.deinit();

        var path_matched = false;
        var allowed_methods: [7]bool = .{false} ** 7; // one per Method variant
        var allowed_count: usize = 0;

        for (self.routes) |r| {
            if (Route.matchPath(r.pattern, req.path, &params)) {
                path_matched = true;
                if (r.method == req.method) {
                    // Copy params into request
                    req.params = params;
                    log.info("{s} {s} → matched {s} {s}", .{ @tagName(req.method), req.path, @tagName(r.method), r.pattern });
                    r.handler(req, res);
                    return;
                }
                // Track allowed methods for this path
                const method_idx: usize = switch (r.method) {
                    .get => 0,
                    .post => 1,
                    .put => 2,
                    .patch => 3,
                    .delete => 4,
                    .options => 5,
                    .head => 6,
                };
                if (!allowed_methods[method_idx]) {
                    allowed_methods[method_idx] = true;
                    allowed_count += 1;
                }
            }
        }

        if (path_matched) {
            // Path matched but method didn't — 405 Method Not Allowed
            _ = res.status(405);
            // Build Allow header value manually
            var buf: [128]u8 = undefined;
            var pos: usize = 0;
            const method_names = [_]struct { Method, []const u8 }{
                .{ .get, "GET" },
                .{ .post, "POST" },
                .{ .put, "PUT" },
                .{ .patch, "PATCH" },
                .{ .delete, "DELETE" },
                .{ .options, "OPTIONS" },
                .{ .head, "HEAD" },
            };
            var first = true;
            for (method_names, 0..) |entry, i| {
                if (allowed_methods[i]) {
                    if (!first) {
                        buf[pos] = ',';
                        pos += 1;
                        buf[pos] = ' ';
                        pos += 1;
                    }
                    const name = entry[1];
                    @memcpy(buf[pos .. pos + name.len], name);
                    pos += name.len;
                    first = false;
                }
            }
            // Allocate the Allow value so it survives beyond this stack frame
            const allow_val = res.allocator.alloc(u8, pos) catch {
                _ = res.header("Allow", "GET");
                res.text("Method Not Allowed") catch {};
                return;
            };
            @memcpy(allow_val[0..pos], buf[0..pos]);
            res.owned_header_values.append(res.allocator, allow_val) catch {};
            _ = res.header("Allow", allow_val);
            res.text("Method Not Allowed") catch {};
            log.warn("{s} {s} → 405 (path matched, method mismatch)", .{ @tagName(req.method), req.path });
            return;
        }

        // No path match — 404
        self.not_found_handler(req, res);
        log.warn("{s} {s} → 404 (no route matched)", .{ @tagName(req.method), req.path });
    }
};

test {
    std.testing.refAllDecls(@This());
}
