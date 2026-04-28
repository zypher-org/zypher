/// zypher ORM — compile-time schema definitions and query builder.
const std = @import("std");

// Phase 5 implementations will add sqlite.zig, schema.zig, query.zig, migration.zig

test {
    std.testing.refAllDecls(@This());
}
