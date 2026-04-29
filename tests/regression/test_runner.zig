// Regression test runner — imports all regression test files.
test {
    _ = @import("router_leak_test.zig");
    _ = @import("middleware_leak_test.zig");
    _ = @import("escaping_test.zig");
}
