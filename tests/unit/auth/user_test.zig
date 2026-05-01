const std = @import("std");
const user_mod = @import("zypher").auth.user;
const password = @import("zypher").auth.password;

const User = user_mod.User;

// ── User creation ────────────────────────────────────────────────────────

test "user: create user with hashed password" {
    var u = try User.init(std.testing.allocator, "alice", "secret123");
    defer u.deinit();
    try std.testing.expectEqualStrings("alice", u.username);
    try std.testing.expect(u.password_hash.len > 0);
}

test "user: authenticate with correct password" {
    var u = try User.init(std.testing.allocator, "bob", "mypassword");
    defer u.deinit();
    try std.testing.expect(try u.authenticate("mypassword"));
}

test "user: authenticate fails with wrong password" {
    var u = try User.init(std.testing.allocator, "carol", "mypassword");
    defer u.deinit();
    try std.testing.expect(!try u.authenticate("wrongpassword"));
}

// ── User roles ────────────────────────────────────────────────────────────

test "user: default role is user" {
    var u = try User.init(std.testing.allocator, "dave", "pass");
    defer u.deinit();
    try std.testing.expectEqualStrings("user", u.role);
}

test "user: set admin role" {
    var u = try User.init(std.testing.allocator, "eve", "pass");
    defer u.deinit();
    u.setRole("admin");
    try std.testing.expectEqualStrings("admin", u.role);
}

// ── User is_active ────────────────────────────────────────────────────────

test "user: default is_active is true" {
    var u = try User.init(std.testing.allocator, "frank", "pass");
    defer u.deinit();
    try std.testing.expect(u.is_active);
}

test "user: deactivate user" {
    var u = try User.init(std.testing.allocator, "grace", "pass");
    defer u.deinit();
    u.deactivate();
    try std.testing.expect(!u.is_active);
}

test "user: inactive user cannot authenticate" {
    var u = try User.init(std.testing.allocator, "heidi", "pass");
    defer u.deinit();
    u.deactivate();
    try std.testing.expect(!try u.authenticate("pass"));
}
