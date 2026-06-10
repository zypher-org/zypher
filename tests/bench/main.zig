const std = @import("std");

const zypher = @import("zypher");

const runs = 5000;
const template_run_count = 500;

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

    std.debug.print("\nDone.\n", .{});
}
