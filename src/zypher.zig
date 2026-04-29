/// zypher — A Django-inspired, batteries-included web framework for Zig.
/// Every abstraction is explicit, inspectable, and replaceable.
/// No hidden allocations, no runtime magic, no global state.
const std = @import("std");

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
};

// Re-export forms (Phase 6)
pub const forms = @import("forms/form.zig");

// Re-export auth (Phase 7)
pub const auth = @import("auth/session.zig");

// Re-export admin (Phase 8)
pub const admin = @import("admin/registry.zig");

// Re-export CLI (Phase 9)
pub const cli = @import("cli/main.zig");

test {
    std.testing.refAllDecls(@This());
}
