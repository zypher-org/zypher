// Unit test runner — imports all unit test files.
test {
    _ = @import("log_test.zig");
    _ = @import("errors_test.zig");
    _ = @import("core/request_test.zig");
    _ = @import("core/response_test.zig");
    _ = @import("core/server_test.zig");
    _ = @import("core/app_test.zig");
    _ = @import("router/route_test.zig");
    _ = @import("router/params_test.zig");
    _ = @import("router/router_test.zig");
}
