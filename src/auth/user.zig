/// zypher auth — user model and authentication views.
const std = @import("std");
const log = std.log.scoped(.user);
const password = @import("password.zig");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;

/// User model with hashed password, role, and active status.
pub const User = struct {
    username: []const u8,
    password_hash: []const u8,
    role: []const u8 = "user",
    is_active: bool = true,
    gpa: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new user with a hashed password.
    pub fn init(gpa: std.mem.Allocator, username: []const u8, plaintext: []const u8) !Self {
        const owned_username = try gpa.dupe(u8, username);
        errdefer gpa.free(owned_username);
        const hashed = try password.hash(gpa, plaintext);
        errdefer gpa.free(hashed);

        log.info("created user '{s}'", .{username});
        return .{
            .username = owned_username,
            .password_hash = hashed,
            .gpa = gpa,
        };
    }

    /// Free user resources.
    pub fn deinit(self: *Self) void {
        self.gpa.free(self.username);
        self.gpa.free(self.password_hash);
        if (self.role.ptr != "user".ptr) {
            self.gpa.free(self.role);
        }
    }

    /// Authenticate a user against a plaintext password.
    pub fn authenticate(self: *Self, plaintext: []const u8) !bool {
        if (!self.is_active) return false;
        return password.verify(self.password_hash, plaintext);
    }

    /// Set the user's role.
    pub fn setRole(self: *Self, new_role: []const u8) void {
        const owned = self.gpa.dupe(u8, new_role) catch return;
        // Only free if role was previously heap-allocated (not default literal)
        if (self.role.ptr != "user".ptr) {
            self.gpa.free(self.role);
        }
        self.role = owned;
        log.info("user '{s}' role set to '{s}'", .{ self.username, new_role });
    }

    /// Deactivate the user account.
    pub fn deactivate(self: *Self) void {
        self.is_active = false;
        log.info("user '{s}' deactivated", .{self.username});
    }
};

/// Middleware that requires an authenticated user.
/// If no user is attached to the request (via session middleware),
/// redirects to /login with a 302 status.
pub fn loginRequired(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    if (req.user == null) {
        log.warn("unauthenticated access to {s}, redirecting to login", .{req.path});
        _ = res.status(302);
        _ = res.header("Location", "/login");
        return;
    }
    next(req, res);
}

/// Middleware that requires an authenticated superuser (admin).
/// If no user or user is not admin, returns 403 Forbidden.
pub fn superuserRequired(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    if (req.user == null) {
        log.warn("unauthenticated access to {s}, redirecting to login", .{req.path});
        _ = res.status(302);
        _ = res.header("Location", "/login");
        return;
    }
    const user: *User = @ptrCast(@alignCast(req.user.?));
    if (!std.mem.eql(u8, user.role, "admin")) {
        log.warn("non-admin access to {s} by user '{s}'", .{ req.path, user.username });
        _ = res.status(403);
        res.text("Forbidden: admin access required") catch {};
        return;
    }
    next(req, res);
}

test {
    std.testing.refAllDecls(@This());
}
