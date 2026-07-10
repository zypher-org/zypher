// Unit test runner — imports all unit test files.
const build_config = @import("build_config");
test {
    _ = @import("test_io");
    _ = @import("build_options_test.zig");
    _ = @import("log_test.zig");
    _ = @import("errors_test.zig");
    _ = @import("core/request_test.zig");
    _ = @import("core/response_test.zig");
    _ = @import("core/server_test.zig");
    _ = @import("core/app_test.zig");
    _ = @import("core/io_audit_test.zig");
    _ = @import("router/route_test.zig");
    _ = @import("router/params_test.zig");
    _ = @import("router/router_test.zig");
    _ = @import("middleware/chain_test.zig");
    _ = @import("middleware/logger_test.zig");
    _ = @import("middleware/cors_test.zig");
    _ = @import("middleware/csrf_test.zig");
    _ = @import("middleware/rate_limit_test.zig");
    _ = @import("middleware/session_test.zig");
    _ = @import("middleware/static_test.zig");
    _ = @import("middleware/compress_test.zig");
    _ = @import("middleware/security_headers_test.zig");
    _ = @import("template/lexer_test.zig");
    _ = @import("template/parser_test.zig");
    _ = @import("template/renderer_test.zig");
    _ = @import("template/filters_test.zig");
    _ = @import("orm/sqlite_test.zig");
    _ = @import("orm/schema_test.zig");
    _ = @import("orm/query_test.zig");
    _ = @import("orm/migration_test.zig");
    _ = @import("orm/driver_interface_test.zig");
    _ = @import("orm/sqlite_driver_test.zig");
    _ = @import("orm/dialect_test.zig");
    if (build_config.has_postgres) {
        _ = @import("orm/postgres_driver_test.zig");
    }
    if (build_config.has_mysql) {
        _ = @import("orm/mysql_driver_test.zig");
    }
    _ = @import("orm/document_test.zig");
    _ = @import("orm/kv_test.zig");
    _ = @import("orm/config_test.zig");
    _ = @import("forms/validators_test.zig");
    _ = @import("forms/form_test.zig");
    _ = @import("auth/session_test.zig");
    _ = @import("auth/password_test.zig");
    _ = @import("auth/user_test.zig");
    _ = @import("admin/registry_test.zig");
    _ = @import("cli_test.zig");
}
