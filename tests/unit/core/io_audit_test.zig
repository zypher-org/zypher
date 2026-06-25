/// Compile-time audit: every key public function signature includes `io: std.Io`.
const std = @import("std");
const testing = std.testing;

const zypher = @import("zypher");
const Server = zypher.core.Server;
const App = zypher.core.App;
const TemplateEngine = zypher.template.renderer.TemplateEngine;
const MigrationRunner = zypher.orm.migration.MigrationRunner;
const Response = zypher.core.Response;
const MiddlewareFn = zypher.middleware.MiddlewareFn;

fn resolveFnType(comptime T: type) ?type {
    const info = @typeInfo(T);
    if (info == .@"fn") return T;
    if (info == .pointer) {
        const child = info.pointer.child;
        if (@typeInfo(child) == .@"fn") return child;
    }
    return null;
}

fn fnHasIoAt(comptime T: type, comptime index: usize) bool {
    const fn_type = resolveFnType(T) orelse return false;
    const fn_info = @typeInfo(fn_type).@"fn";
    if (index >= fn_info.param_types.len) return false;
    const param_type = fn_info.param_types[index] orelse return false;
    return param_type == std.Io;
}

fn assertFnHasIo(comptime name: []const u8, comptime T: type, comptime index: usize) void {
    if (!fnHasIoAt(T, index)) {
        @compileError(name ++ " must accept io: std.Io at parameter index " ++ std.fmt.comptimePrint("{d}", .{index}));
    }
}

comptime {
    assertFnHasIo("Server.listenAndServe", @TypeOf(Server.listenAndServe), 1);
    assertFnHasIo("App.listenAndServe", @TypeOf(App.listenAndServe), 1);
    assertFnHasIo("App.shutdown", @TypeOf(App.shutdown), 1);
    assertFnHasIo("Response.send", @TypeOf(Response.send), 1);
    assertFnHasIo("TemplateEngine.load", @TypeOf(TemplateEngine.load), 1);
    assertFnHasIo("MigrationRunner.migrate", @TypeOf(MigrationRunner.migrate), 2);
    assertFnHasIo("MiddlewareFn", MiddlewareFn, 0);
}

comptime {
    const info = @typeInfo(App);
    if (info == .@"struct") {
        for (info.@"struct".field_types, info.@"struct".field_names) |ft, fn_name| {
            if (ft == std.Io) {
                @compileError("App must not store an io field — io is always caller-supplied (found field '" ++ fn_name ++ "')");
            }
        }
    }
}

test "io audit: compile-time assertions pass" {
    try testing.expect(true);
}

test "io audit: io param detection works" {
    try testing.expect(fnHasIoAt(@TypeOf(Server.listenAndServe), 1));
    try testing.expect(!fnHasIoAt(@TypeOf(Server.listenAndServe), 2));
    try testing.expect(fnHasIoAt(@TypeOf(Response.send), 1));
    try testing.expect(fnHasIoAt(MiddlewareFn, 0));
    try testing.expect(!fnHasIoAt(@TypeOf(Server.init), 0));
}
