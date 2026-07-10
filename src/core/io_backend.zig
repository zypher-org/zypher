const std = @import("std");
const options = @import("options");

pub const IoBackend = enum {
    single_threaded,
    threaded,
    evented,
};

pub const ZypherIo = union(IoBackend) {
    single_threaded: std.Io.Threaded,
    threaded: std.Io.Threaded,
    evented: if (options.io_evented) std.Io.Evented else @compileError(
        "IoBackend.evented requires rebuilding with -Dio_evented=true.\n" ++
            "std.Io.Evented is experimental: networking may fail on some platforms.",
    ),

    pub fn init(gpa: std.mem.Allocator, backend: IoBackend, thread_count: ?u32) !ZypherIo {
        switch (backend) {
            .single_threaded => {
                return .{ .single_threaded = std.Io.Threaded.init_single_threaded };
            },
            .threaded => {
                const cpu_count: u32 = if (thread_count) |tc| tc else brk: {
                    break :brk @max(1, std.Thread.getCpuCount() catch 2);
                };
                return .{ .threaded = std.Io.Threaded.init(gpa, .{
                    .async_limit = .limited(cpu_count),
                    .concurrent_limit = .limited(cpu_count),
                }) };
            },
            .evented => {
                if (!options.io_evented) @compileError(
                    "IoBackend.evented requires rebuilding with -Dio_evented=true.\n" ++
                        "std.Io.Evented is experimental: networking may fail on some platforms.",
                );
                var ev: std.Io.Evented = undefined;
                try ev.init(gpa, .{});
                return .{ .evented = ev };
            },
        }
    }

    pub fn io(self: *ZypherIo) std.Io {
        return switch (self.*) {
            .single_threaded => |*t| t.io(),
            .threaded => |*t| t.io(),
            .evented => |*e| e.io(),
        };
    }

    pub fn deinit(self: *ZypherIo) void {
        switch (self.*) {
            .single_threaded => |*t| t.deinit(),
            .threaded => |*t| t.deinit(),
            .evented => |*e| e.deinit(),
        }
    }
};

const log = std.log.scoped(.io_backend);
