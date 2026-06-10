const std = @import("std");

const zypher = @import("zypher");

const runs = 5000;
const template_run_count = 500;
const router_run_count = 10000;
const orm_run_count = 1000;

fn nowMs() i64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return ts.sec * 1000 + @divFloor(ts.nsec, 1_000_000);
}

fn benchNoop(allocator: std.mem.Allocator) u64 {
    _ = allocator;
    const start = nowMs();
    var i: u64 = 0;
    while (i < runs) : (i += 1) {
        std.mem.doNotOptimizeAway(i);
    }
    const elapsed = @as(u64, @intCast(nowMs() - start));
    return elapsed;
}

fn benchTemplateRender(allocator: std.mem.Allocator) !u64 {
    var engine = zypher.template.renderer.TemplateEngine.init(allocator);
    defer engine.deinit();
    _ = try engine.load("hello.html",
        \\<html><body><h1>{{ title }}</h1><p>{{ body }}</p></body></html>
    );

    var ctx = zypher.template.renderer.Context.init(allocator);
    defer ctx.deinit();
    try ctx.put("title", .{ .string = "Hello World" });
    try ctx.put("body", .{ .string = "This is a benchmark template." });

    const start = nowMs();
    var i: u64 = 0;
    while (i < template_run_count) : (i += 1) {
        var aw = std.Io.Writer.Allocating.init(allocator);
        defer aw.deinit();
        try engine.render("hello.html", &ctx, &aw.writer);
    }
    const elapsed = @as(u64, @intCast(nowMs() - start));
    return elapsed;
}

const Route = zypher.router.Route;
const Router = zypher.router.Router;
const Request = zypher.core.Request;
const Response = zypher.core.Response;

fn _bh1(_: *Request, _: *Response) void {}
fn _bh2(_: *Request, _: *Response) void {}
fn _bh3(_: *Request, _: *Response) void {}
fn _bh4(_: *Request, _: *Response) void {}
fn _bh5(_: *Request, _: *Response) void {}
fn _bhf(_: *Request, _: *Response) void {}

fn benchRouterDispatch(allocator: std.mem.Allocator) !u64 {
    const routes = [_]Route{
        Route.init(.get, "/", _bh1),
        Route.init(.get, "/users/:id", _bh2),
        Route.init(.post, "/users", _bh3),
        Route.init(.get, "/users/:id/posts", _bh4),
        Route.init(.get, "/static/*", _bh5),
    };

    var req = Request{
        .method = .get,
        .path = "/users/42",
        .query = std.StringHashMap([]const u8).init(allocator),
        .headers = std.StringHashMap([]const u8).init(allocator),
        .body = "",
        .params = undefined,
        .allocator = allocator,
    };
    defer req.headers.deinit();
    defer req.query.deinit();

    var res = Response.init(allocator);
    defer res.deinit();

    const router = Router.initFromSlice(&routes, _bhf);

    const start = nowMs();
    var i: u64 = 0;
    while (i < router_run_count) : (i += 1) {
        router.dispatch(&req, &res);
    }
    const elapsed = @as(u64, @intCast(nowMs() - start));
    return elapsed;
}

fn benchOrmQuery(allocator: std.mem.Allocator) !u64 {
    const sqlite = zypher.orm.sqlite;
    const query = zypher.orm.query;
    const schema = zypher.orm.schema;

    const BenchFields = struct {
        id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
        name: schema.FieldDef = schema.Field("name", .text, .{}),
    };
    const TestModel = schema.Model("test_bench", BenchFields);

    var db = try sqlite.Db.open(allocator, ":memory:");
    defer db.close();

    db.exec(TestModel.create_table_sql) catch {};
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        _ = query.create(TestModel, &db, &.{.{ .text = "bench" }}) catch {};
    }

    const start = nowMs();
    i = 0;
    while (i < orm_run_count) : (i += 1) {
        _ = query.all(TestModel, &db, allocator) catch {};
    }
    const elapsed = @as(u64, @intCast(nowMs() - start));

    return elapsed;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("zypher Benchmarks\n", .{});
    std.debug.print("=================\n\n", .{});

    {
        const elapsed = benchNoop(allocator);
        std.debug.print("noop overhead ({d}x):  {} ms\n", .{ runs, elapsed });
    }

    {
        const elapsed = try benchTemplateRender(allocator);
        std.debug.print("template render ({d}x): {} ms\n", .{ template_run_count, elapsed });
    }

    {
        const elapsed = try benchRouterDispatch(allocator);
        std.debug.print("router dispatch ({d}x): {} ms\n", .{ router_run_count, elapsed });
    }

    {
        const elapsed = try benchOrmQuery(allocator);
        std.debug.print("orm query ({d}x): {} ms\n", .{ orm_run_count, elapsed });
    }

    std.debug.print("\nDone.\n", .{});
}
