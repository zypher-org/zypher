/// zypher — A Django-inspired, batteries-included web framework for Zig.
/// Every abstraction is explicit, inspectable, and replaceable.
/// No hidden allocations, no runtime magic, no global state.
const std = @import("std");
const build_config = @import("build_config");

pub const version = build_config.version;

pub const log = @import("log.zig");
pub const errors = @import("errors.zig");

// Re-export core primitives (Phase 1)
pub const core = @import("core/main.zig");

// Re-export router (Phase 2)
pub const router = struct {
    pub const Route = @import("router/route.zig").Route;
    pub const RouteParams = @import("router/params.zig").RouteParams;
    pub const Router = @import("router/router.zig").Router;
};

// Re-export middleware (Phase 3)
pub const middleware = struct {
    pub const Chain = @import("middleware/chain.zig").Chain;
    pub const MiddlewareFn = @import("middleware/chain.zig").MiddlewareFn;
    pub const HandlerFn = @import("middleware/chain.zig").HandlerFn;
    pub const logger = @import("middleware/logger.zig");
    pub const cors = @import("middleware/cors.zig");
    pub const csrf = @import("middleware/csrf.zig");
    pub const rate_limit = @import("middleware/rate_limit.zig");
    pub const static = @import("middleware/static.zig");
    pub const compress = @import("middleware/compress.zig");
    pub const session = @import("middleware/session.zig");
    pub const security_headers = @import("middleware/security_headers.zig");
    pub const recovery = @import("middleware/recovery.zig");
};

// Re-export template (Phase 4)
pub const template = struct {
    pub const lexer = @import("template/lexer.zig");
    pub const parser = @import("template/parser.zig");
    pub const renderer = @import("template/renderer.zig");
    pub const filters = @import("template/filters.zig");
};

// Re-export ORM (Phase 5)
pub const orm = struct {
    pub const sqlite = @import("orm/sqlite.zig");
    pub const schema = @import("orm/schema.zig");
    pub const query = @import("orm/query.zig");
    pub const QuerySet = @import("orm/query.zig").QuerySet;
    pub const migration = @import("orm/migration.zig");
    pub const driver = struct {
        pub const interface = @import("orm/driver/interface.zig");
        pub const sqlite = @import("orm/driver/sqlite.zig");
    };
};

// Re-export forms (Phase 6)
pub const forms = struct {
    pub const validators = @import("forms/validators.zig");
    pub const form = @import("forms/form.zig");
};

// Re-export auth (Phase 7)
pub const auth = struct {
    pub const session = @import("auth/session.zig");
    pub const password = @import("auth/password.zig");
    pub const user = @import("auth/user.zig");
};

// Re-export admin (Phase 8)
pub const admin = @import("admin/registry.zig");

// Re-export CLI runner (Phase 9)
pub const cli_runner = @import("cli/runner.zig");

test {
    std.testing.refAllDecls(@This());
}
