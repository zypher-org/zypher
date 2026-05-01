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
    _ = @import("middleware/chain_test.zig");
    _ = @import("middleware/logger_test.zig");
    _ = @import("middleware/cors_test.zig");
    _ = @import("middleware/csrf_test.zig");
    _ = @import("middleware/rate_limit_test.zig");
    _ = @import("middleware/static_test.zig");
    _ = @import("middleware/compress_test.zig");
    _ = @import("template/lexer_test.zig");
    _ = @import("template/parser_test.zig");
    _ = @import("template/renderer_test.zig");
    _ = @import("template/filters_test.zig");
    _ = @import("orm/sqlite_test.zig");
    _ = @import("orm/schema_test.zig");
    _ = @import("orm/query_test.zig");
    _ = @import("orm/migration_test.zig");
    _ = @import("forms/validators_test.zig");
    _ = @import("forms/form_test.zig");
    _ = @import("auth/session_test.zig");
}
