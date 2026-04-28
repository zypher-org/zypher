/// Unit tests for zypher Rate Limiter middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const rate_limit = @import("zypher").middleware.rate_limit;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;

fn makeRequest(gpa: std.mem.Allocator, method: @import("zypher").core.Method, path: []const u8) Request {
    return .{
        .method = method,
        .path = path,
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
}

fn ok_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("ok") catch {};
}

test "Rate limit: under limit passes through" {
    const gpa = std.testing.allocator;

    const RL = rate_limit.middlewareWith(.{ .max_requests = 5, .window_seconds = 60 });
    defer RL.deinit();
    const MyChain = comptime Chain(.{RL.middleware()});

    var req = makeRequest(gpa, .get, "/api");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "Rate limit: over limit returns 429" {
    const gpa = std.testing.allocator;

    const RL = rate_limit.middlewareWith(.{ .max_requests = 2, .window_seconds = 60 });
    defer RL.deinit();
    const MyChain = comptime Chain(.{RL.middleware()});

    // First two requests should pass
    {
        var req = makeRequest(gpa, .get, "/api");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        MyChain.run(&req, &res, ok_handler);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }
    {
        var req = makeRequest(gpa, .get, "/api");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        MyChain.run(&req, &res, ok_handler);
        try std.testing.expectEqual(@as(u16, 200), res.status_code);
    }
    // Third request should be rate limited
    {
        var req = makeRequest(gpa, .get, "/api");
        defer req.deinit();
        var res = Response.init(gpa);
        defer res.deinit();
        MyChain.run(&req, &res, ok_handler);
        try std.testing.expectEqual(@as(u16, 429), res.status_code);
        const retry = res.headers.get("Retry-After");
        try std.testing.expect(retry != null);
    }
}
