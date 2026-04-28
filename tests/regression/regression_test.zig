// Regression test runner — imports all regression test files.
test {
    _ = @import("memory_leak_test.zig");
    _ = @import("router_leak_test.zig");
}
