const std = @import("std");

const zypher = @import("zypher");

pub const std_options: std.Options = .{
    .log_level = .err,
};

const baseline_noop_runs = 1_000_000;
const template_simple_runs = 2_000;
const template_aggressive_runs = 400;
const template_list_items = 128;
const router_baseline_runs = 50_000;
const router_aggressive_runs = 20_000;
const router_aggressive_routes = 256;
const middleware_runs = 100_000;
const orm_seed_rows = 2_000;
const orm_write_rows = 1_000;
const orm_lookup_runs = 5_000;
const orm_filter_runs = 500;
const orm_scan_runs = 100;

fn nowNs() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
    return (@as(i128, ts.sec) * std.time.ns_per_s) + ts.nsec;
}

fn elapsedNs(start: i128) u64 {
    return @intCast(nowNs() - start);
}

fn printBench(name: []const u8, ops: u64, ns: u64) void {
    const ns_per_op = if (ops == 0) 0 else ns / ops;
    const ops_per_sec = if (ns == 0) 0 else (ops * std.time.ns_per_s) / ns;
    std.debug.print("{s:<34} {d:>10} ops  {d:>10} ns/op  {d:>10} ops/s  {d:>8} ms\n", .{
        name,
        ops,
        ns_per_op,
        ops_per_sec,
        ns / std.time.ns_per_ms,
    });
}

fn benchNoop() u64 {
    const start = nowNs();
    var i: u64 = 0;
    while (i < baseline_noop_runs) : (i += 1) {
        std.mem.doNotOptimizeAway(i);
    }
    return elapsedNs(start);
}

fn benchTemplateRenderSimple(allocator: std.mem.Allocator) !u64 {
    var engine = zypher.template.renderer.TemplateEngine.init(allocator);
    defer engine.deinit();
    _ = try engine.loadFromSource("hello.html",
        \\<html><body><h1>{{ title }}</h1><p>{{ body }}</p></body></html>
    );

    var ctx = zypher.template.renderer.Context.init(allocator);
    defer ctx.deinit();
    try ctx.put("title", .{ .string = "Hello World" });
    try ctx.put("body", .{ .string = "This is a benchmark template." });

    const start = nowNs();
    var i: u64 = 0;
    while (i < template_simple_runs) : (i += 1) {
        var aw = std.Io.Writer.Allocating.init(allocator);
        defer aw.deinit();
        try engine.render("hello.html", &ctx, &aw.writer);
        std.mem.doNotOptimizeAway(aw.writer.end);
    }
    return elapsedNs(start);
}

fn benchTemplateRenderAggressive(allocator: std.mem.Allocator) !u64 {
    var engine = zypher.template.renderer.TemplateEngine.init(allocator);
    defer engine.deinit();
    _ = try engine.loadFromSource("base.html",
        \\<html>
        \\<head><title>{{ title }}</title></head>
        \\<body>
        \\{% block content %}<p>fallback</p>{% endblock %}
        \\{% include "footer.html" %}
        \\</body>
        \\</html>
    );
    _ = try engine.loadFromSource("row.html",
        \\<article data-index="{{ forloop.counter0 }}">
        \\  <h2>{{ item }}</h2>
        \\  <p>{{ body }}</p>
        \\</article>
    );
    _ = try engine.loadFromSource("footer.html",
        \\<footer>{{ footer }}</footer>
    );
    _ = try engine.loadFromSource("page.html",
        \\{% extends "base.html" %}
        \\{% block content %}
        \\{% if title %}
        \\<section>
        \\{% for item in items %}
        \\{% include "row.html" %}
        \\{% endfor %}
        \\</section>
        \\{% else %}
        \\<p>missing title</p>
        \\{% endif %}
        \\{% endblock %}
    );

    var item_values: [template_list_items]zypher.template.renderer.Value = undefined;
    for (&item_values, 0..) |*value, i| {
        value.* = .{ .string = if (i % 2 == 0) "Alpha <escaped>" else "Beta & escaped" };
    }

    var ctx = zypher.template.renderer.Context.init(allocator);
    defer ctx.deinit();
    try ctx.put("title", .{ .string = "Aggressive Template" });
    try ctx.put("body", .{ .string = "Nested include and loop payload with escaping." });
    try ctx.put("footer", .{ .string = "Rendered by Zypher" });
    try ctx.put("items", .{ .list = item_values[0..] });

    const start = nowNs();
    var i: u64 = 0;
    while (i < template_aggressive_runs) : (i += 1) {
        var aw = std.Io.Writer.Allocating.init(allocator);
        defer aw.deinit();
        try engine.render("page.html", &ctx, &aw.writer);
        std.mem.doNotOptimizeAway(aw.writer.end);
    }
    return elapsedNs(start);
}

const Route = zypher.router.Route;
const Router = zypher.router.Router;
const Request = zypher.core.Request;
const Response = zypher.core.Response;

fn _bh(_: *Request, _: *Response) void {}
fn _bhf(_: *Request, _: *Response) void {}

fn makeRequest(allocator: std.mem.Allocator, method: zypher.core.Method, path: []const u8) Request {
    return .{
        .method = method,
        .path = path,
        .query = std.StringHashMap([]const u8).init(allocator),
        .headers = std.StringHashMap([]const u8).init(allocator),
        .body = "",
        .params = undefined,
        .allocator = allocator,
    };
}

fn benchRouterDispatchBaseline(allocator: std.mem.Allocator) !u64 {
    const routes = [_]Route{
        Route.init(.get, "/", _bh),
        Route.init(.get, "/users/:id", _bh),
        Route.init(.post, "/users", _bh),
        Route.init(.get, "/users/:id/posts", _bh),
        Route.init(.get, "/static/*", _bh),
    };

    var req = makeRequest(allocator, .get, "/users/42");
    defer req.deinit();
    var res = Response.init(allocator);
    defer res.deinit();

    const router = Router.initFromSlice(&routes, _bhf);

    const start = nowNs();
    var i: u64 = 0;
    while (i < router_baseline_runs) : (i += 1) {
        router.dispatch(&req, &res);
    }
    return elapsedNs(start);
}

fn makeAggressiveRoutes(comptime count: usize) [count]Route {
    comptime {
        @setEvalBranchQuota(200_000);
        var routes: [count]Route = undefined;
        for (&routes, 0..) |*route, i| {
            route.* = Route.init(.get, std.fmt.comptimePrint("/tenant/:tenant/resources/{d}/items/:item", .{i}), _bh);
        }
        return routes;
    }
}

fn benchRouterDispatchAggressive(allocator: std.mem.Allocator) !u64 {
    const routes = comptime makeAggressiveRoutes(router_aggressive_routes);
    var req = makeRequest(allocator, .get, "/tenant/acme/resources/255/items/999");
    defer req.deinit();
    var res = Response.init(allocator);
    defer res.deinit();

    const router = Router.initFromSlice(&routes, _bhf);

    const start = nowNs();
    var i: u64 = 0;
    while (i < router_aggressive_runs) : (i += 1) {
        router.dispatch(&req, &res);
    }
    return elapsedNs(start);
}

fn mwPass(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    next(io, req, res);
}

fn mwHeader(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    _ = res.header("X-Bench", "1");
    next(io, req, res);
}

fn mwCookie(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    _ = req.cookie("sid");
    next(io, req, res);
}

fn terminalHandler(_: *Request, res: *Response) void {
    res.text("ok") catch {};
}

fn benchMiddlewareAggressive(allocator: std.mem.Allocator, io: std.Io) !u64 {
    const Chain = zypher.middleware.Chain(.{
        mwPass,
        mwHeader,
        mwCookie,
        mwPass,
        mwHeader,
        mwCookie,
        mwPass,
        mwHeader,
        mwCookie,
        mwPass,
        mwHeader,
        mwCookie,
    });

    var req = makeRequest(allocator, .get, "/bench");
    defer req.deinit();
    try req.headers.put("Cookie", "sid=abc; theme=dark; locale=en");
    var res = Response.init(allocator);
    defer res.deinit();

    const start = nowNs();
    var i: u64 = 0;
    while (i < middleware_runs) : (i += 1) {
        Chain.run(io, &req, &res, terminalHandler);
    }
    return elapsedNs(start);
}

const sqlite = zypher.orm.sqlite;
const driver_iface = zypher.orm.driver.interface;
const RelationalDb = driver_iface.RelationalDb;
const Value = driver_iface.Value;
const query = zypher.orm.query;
const schema = zypher.orm.schema;

const BenchFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    name: schema.FieldDef = schema.Field("name", .text, .{}),
    score: schema.FieldDef = schema.Field("score", .integer, .{}),
    active: schema.FieldDef = schema.Field("active", .boolean, .{}),
};
const BenchModel = schema.Model("test_bench_aggressive", BenchFields);

fn freeRows(comptime M: type, allocator: std.mem.Allocator, rows: *std.ArrayList(query.RowType(M))) void {
    for (rows.items) |*row| query.freeRow(M, allocator, row);
    rows.deinit(allocator);
}

fn setupBenchDb(allocator: std.mem.Allocator) !sqlite.Db {
    var sdb = try sqlite.Db.open(allocator, ":memory:");
    errdefer sdb.close();
    const db = sdb.asRelationalDb();
    try sdb.exec(BenchModel.create_table_sql);
    try sdb.exec("BEGIN");
    var i: u64 = 0;
    while (i < orm_seed_rows) : (i += 1) {
        const name = if (i % 2 == 0) "even-row" else "odd-row";
        _ = try query.create(BenchModel, db, &.{
            .{ .text = name },
            .{ .int = @intCast(i) },
            .{ .int = if (i % 3 == 0) 1 else 0 },
        });
    }
    try sdb.exec("COMMIT");
    return sdb;
}

fn benchOrmWriteAggressive(allocator: std.mem.Allocator) !u64 {
    var sdb = try sqlite.Db.open(allocator, ":memory:");
    defer sdb.close();
    const db = sdb.asRelationalDb();
    try sdb.exec(BenchModel.create_table_sql);

    const start = nowNs();
    try sdb.exec("BEGIN");
    var i: u64 = 0;
    while (i < orm_write_rows) : (i += 1) {
        _ = try query.create(BenchModel, db, &.{
            .{ .text = "write-row" },
            .{ .int = @intCast(i) },
            .{ .int = 1 },
        });
    }
    try sdb.exec("COMMIT");
    return elapsedNs(start);
}

fn benchOrmLookupAggressive(allocator: std.mem.Allocator) !u64 {
    var sdb = try setupBenchDb(allocator);
    defer sdb.close();
    const db = sdb.asRelationalDb();

    const start = nowNs();
    var i: u64 = 0;
    while (i < orm_lookup_runs) : (i += 1) {
        var row = try query.getById(BenchModel, db, allocator, @intCast((i % orm_seed_rows) + 1));
        query.freeRow(BenchModel, allocator, &row);
    }
    return elapsedNs(start);
}

fn benchOrmFilterAggressive(allocator: std.mem.Allocator) !u64 {
    var sdb = try setupBenchDb(allocator);
    defer sdb.close();
    const db = sdb.asRelationalDb();

    const start = nowNs();
    var i: u64 = 0;
    while (i < orm_filter_runs) : (i += 1) {
        var qs = query.QuerySet(BenchModel).init(db, allocator);
        defer qs.deinit();
        const rows = try qs.filterBy("active = ?", &.{.{ .int = 1 }}).orderBy("score DESC").limit(25).offset(10).exec();
        var mutable_rows = rows;
        freeRows(BenchModel, allocator, &mutable_rows);
    }
    return elapsedNs(start);
}

fn benchOrmScanAggressive(allocator: std.mem.Allocator) !u64 {
    var sdb = try setupBenchDb(allocator);
    defer sdb.close();
    const db = sdb.asRelationalDb();

    const start = nowNs();
    var i: u64 = 0;
    while (i < orm_scan_runs) : (i += 1) {
        var rows = try query.all(BenchModel, db, allocator);
        freeRows(BenchModel, allocator, &rows);
    }
    return elapsedNs(start);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const previous_log_level = zypher.log.getLogLevel();
    zypher.log.setLogLevel(.err);
    defer zypher.log.setLogLevel(previous_log_level);

    var t = std.Io.Threaded.init(allocator, .{});
    defer t.deinit();
    const io = t.io();

    std.debug.print("zypher Benchmarks\n", .{});
    std.debug.print("=================\n\n", .{});

    printBench("noop baseline", baseline_noop_runs, benchNoop());
    printBench("template simple render", template_simple_runs, try benchTemplateRenderSimple(allocator));
    printBench("template aggressive render", template_aggressive_runs, try benchTemplateRenderAggressive(allocator));
    printBench("router baseline dispatch", router_baseline_runs, try benchRouterDispatchBaseline(allocator));
    printBench("router 256-route late match", router_aggressive_runs, try benchRouterDispatchAggressive(allocator));
    printBench("middleware 12-step chain", middleware_runs, try benchMiddlewareAggressive(allocator, io));
    printBench("orm transactional writes", orm_write_rows, try benchOrmWriteAggressive(allocator));
    printBench("orm primary-key lookups", orm_lookup_runs, try benchOrmLookupAggressive(allocator));
    printBench("orm filtered querysets", orm_filter_runs, try benchOrmFilterAggressive(allocator));
    printBench("orm full table scans", orm_scan_runs, try benchOrmScanAggressive(allocator));

    std.debug.print("\nDone.\n", .{});
}
