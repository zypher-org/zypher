/// Unit tests for zypher Middleware Chain — execution order, short-circuit, mutation.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;

// ── Test helpers ────────────────────────────────────────────────────

var exec_log: std.ArrayList([]const u8) = .empty;

fn resetLog(gpa: std.mem.Allocator) void {
    for (exec_log.items) |entry| gpa.free(entry);
    exec_log.deinit(gpa);
    exec_log = .empty;
}

fn logEntry(gpa: std.mem.Allocator, name: []const u8) void {
    exec_log.append(gpa, gpa.dupe(u8, name) catch unreachable) catch {};
}

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

// ── Middleware that logs execution and calls next ────────────────────

fn mw_a(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    logEntry(req.allocator, "A");
    next(io, req, res);
}

fn mw_b(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    logEntry(req.allocator, "B");
    next(io, req, res);
}

fn mw_c(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    logEntry(req.allocator, "C");
    next(io, req, res);
}

// ── Middleware that short-circuits (does NOT call next) ─────────────

fn mw_short_circuit(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    _ = next;
    _ = io;
    logEntry(req.allocator, "SHORT");
    _ = res.status(403);
    res.text("blocked") catch {};
}

// ── Middleware that mutates request before handler ──────────────────

fn mw_add_header(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    req.headers.put("X-Middleware", "true") catch {};
    next(io, req, res);
}

// ── Middleware that mutates response after handler ──────────────────

fn mw_add_response_header(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    next(io, req, res);
    _ = res.header("X-Post-Middleware", "true");
}

// ── Final handler ──────────────────────────────────────────────────

fn final_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("ok") catch {};
}

// ── Tests ──────────────────────────────────────────────────────────

test "Chain: middleware executes in registered order" {
    const gpa = std.testing.allocator;
    defer resetLog(gpa);

    const MyChain = comptime Chain(.{ mw_a, mw_b, mw_c });

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, final_handler);

    try std.testing.expectEqual(@as(usize, 3), exec_log.items.len);
    try std.testing.expectEqualStrings("A", exec_log.items[0]);
    try std.testing.expectEqualStrings("B", exec_log.items[1]);
    try std.testing.expectEqualStrings("C", exec_log.items[2]);
}

test "Chain: short-circuit prevents later middleware and handler from running" {
    const gpa = std.testing.allocator;
    defer resetLog(gpa);

    const MyChain = comptime Chain(.{ mw_a, mw_short_circuit, mw_c });

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, final_handler);

    try std.testing.expectEqual(@as(usize, 2), exec_log.items.len);
    try std.testing.expectEqualStrings("A", exec_log.items[0]);
    try std.testing.expectEqualStrings("SHORT", exec_log.items[1]);
    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}

test "Chain: middleware can mutate request before handler" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{mw_add_header});

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, final_handler);

    const val = req.headers.get("X-Middleware");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("true", val.?);
}

test "Chain: middleware can mutate response after handler" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{mw_add_response_header});

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, final_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    const val = res.headers.get("X-Post-Middleware");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("true", val.?);
}

test "Chain: empty chain passes straight to handler" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{});

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, final_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "Chain: single middleware runs then handler" {
    const gpa = std.testing.allocator;
    defer resetLog(gpa);

    const MyChain = comptime Chain(.{mw_a});

    var req = makeRequest(gpa, .get, "/");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(std.testing.io, &req, &res, final_handler);

    try std.testing.expectEqual(@as(usize, 1), exec_log.items.len);
    try std.testing.expectEqualStrings("A", exec_log.items[0]);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}
