/// zypher Router — comptime route table with runtime dispatch.
const std = @import("std");
const Method = @import("../core/method.zig").Method;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const Route = @import("route.zig").Route;
const RouteParams = @import("params.zig").RouteParams;
const log = std.log.scoped(.router);

/// Route group — prepends a prefix to all route patterns.
pub fn Group(comptime prefix: []const u8, comptime routes: anytype) []const Route {
    comptime {
        const type_info = @typeInfo(@TypeOf(routes));
        const len = if (type_info == .@"struct") std.meta.fields(@TypeOf(routes)).len else routes.len;
        var prefixed: [len]Route = undefined;
        if (type_info == .@"struct") {
            const field_names = std.meta.fieldNames(@TypeOf(routes));
            for (field_names, 0..) |name, i| {
                const r = @field(routes, name);
                prefixed[i] = Route.init(r.method, prefix ++ r.pattern, r.handler);
            }
        } else {
            for (0..len) |i| {
                const r = routes[i];
                prefixed[i] = Route.init(r.method, prefix ++ r.pattern, r.handler);
            }
        }
        return &prefixed;
    }
}

const MethodBits = u7;

fn methodBit(m: Method) MethodBits {
    return @as(MethodBits, 1) << @intFromEnum(m);
}

fn methodAllowed(bits: MethodBits, m: Method) bool {
    return bits & methodBit(m) != 0;
}

pub const Router = struct {
    routes: []const Route,
    not_found_handler: *const fn (*Request, *Response) void,

    /// Create a route entry for use in a comptime routes tuple.
    pub fn route(m: Method, pattern: []const u8, handler: *const fn (*Request, *Response) void) Route {
        return Route.init(m, pattern, handler);
    }

    /// Create a grouped set of routes with a common prefix.
    pub fn group(comptime prefix: []const u8, comptime routes: anytype) []const Route {
        return Group(prefix, routes);
    }

    /// Initialise the router with a comptime routes tuple/array and a 404 handler.
    pub fn init(comptime routes: anytype, not_found: *const fn (*Request, *Response) void) Router {
        const type_info = @typeInfo(@TypeOf(routes));
        comptime {
            if (type_info != .@"struct" and type_info != .array) {
                @compileError("routes must be a tuple or array, got " ++ @tagName(type_info));
            }
        }
        const route_list = comptime blk: {
            const route_count = if (type_info == .@"struct") cnt: {
                break :cnt std.meta.fieldNames(@TypeOf(routes)).len;
            } else cnt: {
                break :cnt type_info.array.len;
            };
            var list: [route_count]Route = undefined;
            if (type_info == .@"struct") {
                const field_names = std.meta.fieldNames(@TypeOf(routes));
                for (field_names, 0..) |name, i| {
                    const r = @field(routes, name);
                    Route.validatePattern(r.pattern) catch |err| {
                        @compileError("Invalid route pattern '" ++ r.pattern ++ "': " ++ @errorName(err));
                    };
                    list[i] = r;
                }
            } else {
                for (&routes, 0..) |*r, i| {
                    Route.validatePattern(r.pattern) catch |err| {
                        @compileError("Invalid route pattern '" ++ r.pattern ++ "': " ++ @errorName(err));
                    };
                    list[i] = r.*;
                }
            }
            break :blk list;
        };

        return .{
            .routes = &route_list,
            .not_found_handler = not_found,
        };
    }

    /// Initialise the router with a runtime slice of routes and a 404 handler.
    pub fn initFromSlice(routes: []const Route, not_found: *const fn (*Request, *Response) void) Router {
        return .{
            .routes = routes,
            .not_found_handler = not_found,
        };
    }

    /// Dispatch a request to the matching route handler.
    /// - Path match + method match → handler
    /// - Path match + method mismatch → 405 with Allow header
    /// - No path match → 404
    pub fn dispatch(self: *const Router, req: *Request, res: *Response) void {
        var path_segments: [64][]const u8 = undefined;
        var seg_count: usize = 0;
        {
            var it = std.mem.splitScalar(u8, req.path, '/');
            _ = it.next();
            while (it.next()) |seg| {
                if (seg.len > 0) {
                    path_segments[seg_count] = seg;
                    seg_count += 1;
                }
            }
        }

        var candidate_params = RouteParams.init(req.allocator);
        defer candidate_params.deinit();
        var best_params = RouteParams.init(req.allocator);

        var path_matched = false;
        var allowed_methods: MethodBits = 0;
        var best_route: ?Route = null;
        var best_score: usize = 0;

        for (self.routes) |r| {
            if (r.method != req.method) continue;
            if (Route.matchPathSegments(r.pattern, path_segments[0..seg_count], &candidate_params, req.path)) {
                const score = routeSpecificity(r.pattern);
                if (best_route == null or score > best_score) {
                    best_route = r;
                    best_score = score;
                    best_params = candidate_params;
                }
            }
        }

        if (best_route) |r| {
            req.params = best_params;
            log.info("{s} {s} → matched {s} {s}", .{ @tagName(req.method), req.path, @tagName(r.method), r.pattern });
            r.handler(req, res);
            return;
        }

        for (self.routes) |r| {
            if (r.method == req.method) continue;
            if (Route.matchesPath(r.pattern, path_segments[0..seg_count])) {
                path_matched = true;
                allowed_methods |= methodBit(r.method);
            }
        }

        if (path_matched) {
            _ = res.status(405);
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
            inline for (method_names) |entry| {
                if (methodAllowed(allowed_methods, entry[0])) {
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
            _ = res.header("Allow", buf[0..pos]);
            res.text("Method Not Allowed") catch {};
            log.warn("{s} {s} → 405 (path matched, method mismatch)", .{ @tagName(req.method), req.path });
            return;
        }

        self.not_found_handler(req, res);
        log.warn("{s} {s} → 404 (no route matched)", .{ @tagName(req.method), req.path });
    }
};

fn routeSpecificity(pattern: []const u8) usize {
    var score: usize = 0;
    var it = std.mem.splitScalar(u8, pattern, '/');
    _ = it.next();
    while (it.next()) |segment| {
        if (segment.len == 0) continue;
        if (segment[0] == '*') {
            score += 1;
        } else if (segment[0] == ':') {
            score += 10;
        } else {
            score += 100;
        }
    }
    return score;
}

test {
    std.testing.refAllDecls(@This());
}
