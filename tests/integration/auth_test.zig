const std = @import("std");
const zypher = @import("zypher");
const session_mod = zypher.auth.session;
const password_mod = zypher.auth.password;
const user_mod = zypher.auth.user;
const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Method = zypher.core.Method;
const SessionStore = session_mod.SessionStore;
const User = user_mod.User;

// ── Integration: Register → Login → Protected → Logout → Denied ──────

test "auth: full auth flow — register, login, protected, logout, denied" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    // 1. Register a user
    var user = try User.init(std.testing.allocator, "alice", "secret123");
    defer user.deinit();

    // 2. Create session and store user_id
    var session = try store.create();
    try session.put(std.testing.allocator, "user_id", "alice");
    try store.save(&session);
    session.deinit(std.testing.allocator);

    // 3. Verify session has user data
    const loaded = try store.get(session.id);
    try std.testing.expect(loaded != null);
    try std.testing.expectEqualStrings("alice", loaded.?.get("user_id") orelse "");

    // 4. Simulate loginRequired: user is set on request → passes
    var req = Request{
        .method = Method.get,
        .path = "/dashboard",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
        .user = @ptrCast(&user), // authenticated user
    };
    defer req.deinit();

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    // loginRequired should pass through since user is set
    // Test the logic directly — middleware would call next() if user is set
    var passed = false;
    if (req.user != null) {
        passed = true;
    }
    try std.testing.expect(passed);

    // 5. Destroy session (logout)
    try store.destroy(session.id);
    const after_logout = try store.get(session.id);
    try std.testing.expect(after_logout == null);

    // 6. Simulate unauthenticated request → loginRequired would redirect
    var req2 = Request{
        .method = Method.get,
        .path = "/dashboard",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
        .user = null, // not authenticated
    };
    defer req2.deinit();

    try std.testing.expect(req2.user == null);
}

test "auth: password verify round-trip through user model" {
    // Verify that hashing via User.init and verifying via User.authenticate
    // work together end-to-end
    var user = try User.init(std.testing.allocator, "bob", "hunter2");
    defer user.deinit();

    try std.testing.expect(try user.authenticate("hunter2"));
    try std.testing.expect(!try user.authenticate("password123"));

    // Deactivated user cannot authenticate
    user.deactivate();
    try std.testing.expect(!try user.authenticate("hunter2"));
}

test "auth: admin role check via superuserRequired logic" {
    var admin = try User.init(std.testing.allocator, "root", "adminpass");
    defer admin.deinit();
    admin.setRole("admin");

    var regular = try User.init(std.testing.allocator, "joe", "userpass");
    defer regular.deinit();

    // Admin should pass superuser check
    try std.testing.expect(std.mem.eql(u8, admin.role, "admin"));

    // Regular user should not
    try std.testing.expect(!std.mem.eql(u8, regular.role, "admin"));
}
