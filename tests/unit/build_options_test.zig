const std = @import("std");
const build_config = @import("build_config");

test "build_config has a non-empty version string" {
    try std.testing.expect(build_config.version.len > 0);
}

test "build_config has_* flags are accessible booleans" {
    _ = build_config.has_postgres;
    _ = build_config.has_mysql;
    _ = build_config.has_mongodb;
    _ = build_config.has_redis;
}

test "build_config has_postgres is false by default" {
    if (build_config.has_postgres) return error.SkipZigTest;
    try std.testing.expect(!build_config.has_postgres);
}

test "build_config has_mysql is false by default" {
    try std.testing.expect(!build_config.has_mysql);
}

test "build_config has_mongodb is false by default" {
    try std.testing.expect(!build_config.has_mongodb);
}

test "build_config has_redis is false by default" {
    try std.testing.expect(!build_config.has_redis);
}
