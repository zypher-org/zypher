// Integration test runner — imports all integration test files.
test {
    _ = @import("round_trip_test.zig");
    _ = @import("router_test.zig");
    _ = @import("middleware_test.zig");
    _ = @import("template_test.zig");
    _ = @import("orm_test.zig");
}
