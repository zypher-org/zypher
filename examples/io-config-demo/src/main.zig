/// IO Configuration Demo - demonstrates using the IoConfig API.
const std = @import("std");
const zypher = @import("zypher");

const Request = zypher.core.Request;
const Response = zypher.core.Response;
const IoConfig = zypher.core.IoConfig;

fn index(req: *Request, res: *Response) void {
    _ = req;
    res.text("Hello from IO Config Demo!") catch {};
}

/// Parse --port flag from command line.
fn parsePort(args: []const [:0]const u8) u16 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port")) {
            if (i + 1 < args.len) {
                return std.fmt.parseInt(u16, args[i + 1], 10) catch 8080;
            }
        }
    }
    return 8080;
}

pub fn main(init: std.process.Init) !void {
    const args = try std.process.Args.toSlice(init.minimal.args, init.arena.allocator());
    const port = parsePort(args);

    std.log.info("Starting IO Config Demo with default IO model", .{});
    std.log.info("Listening on port: {d}", .{port});

    // Use default IO configuration (recommended for most cases)
    const io_config = IoConfig.default();
    const io = try io_config.createIo(init);

    // Initialize app with a simple handler
    var app = zypher.core.App.init(init.gpa, .{ .host = "127.0.0.1", .port = port });
    defer app.deinit();
    app.handler(index);

    // Start server
    try app.listenAndServe(io);
}
