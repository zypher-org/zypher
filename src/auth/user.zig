/// zypher auth — user model and authentication views.
const std = @import("std");
const log = std.log.scoped(.user);
const password = @import("password.zig");

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

test {
    std.testing.refAllDecls(@This());
}
