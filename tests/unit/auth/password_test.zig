const std = @import("std");
const password = @import("zypher").auth.password;

// ── Hash and verify ──────────────────────────────────────────────────────

test "password: hash produces non-empty output" {
    const hashed = try password.hash(std.testing.allocator, "secret123");
    defer std.testing.allocator.free(hashed);
    try std.testing.expect(hashed.len > 0);
}

test "password: hash is different from plaintext" {
    const hashed = try password.hash(std.testing.allocator, "secret123");
    defer std.testing.allocator.free(hashed);
    try std.testing.expect(!std.mem.eql(u8, hashed, "secret123"));
}

test "password: verify succeeds with correct password" {
    const hashed = try password.hash(std.testing.allocator, "mypassword");
    defer std.testing.allocator.free(hashed);
    try std.testing.expect(try password.verify(hashed, "mypassword"));
}

test "password: verify fails with wrong password" {
    const hashed = try password.hash(std.testing.allocator, "mypassword");
    defer std.testing.allocator.free(hashed);
    try std.testing.expect(!try password.verify(hashed, "wrongpassword"));
}

test "password: same password produces different hashes (salt)" {
    const h1 = try password.hash(std.testing.allocator, "same");
    defer std.testing.allocator.free(h1);
    const h2 = try password.hash(std.testing.allocator, "same");
    defer std.testing.allocator.free(h2);
    try std.testing.expect(!std.mem.eql(u8, h1, h2));
}

// ── Edge cases ────────────────────────────────────────────────────────────

test "password: empty password hashes and verifies" {
    const hashed = try password.hash(std.testing.allocator, "");
    defer std.testing.allocator.free(hashed);
    try std.testing.expect(try password.verify(hashed, ""));
}

test "password: long password hashes and verifies" {
    const long = "a" ** 1000;
    const hashed = try password.hash(std.testing.allocator, long);
    defer std.testing.allocator.free(hashed);
    try std.testing.expect(try password.verify(hashed, long));
}

test "password: verify returns error for malformed hash string" {
    const result = password.verify("not-a-valid-hash", "test");
    try std.testing.expect(result == error.InvalidHashFormat);
}
