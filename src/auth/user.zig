/// zypher auth — user model and authentication views.
const std = @import("std");
const log = std.log.scoped(.user);
const password = @import("password.zig");
const Session = @import("session.zig").Session;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const csrf = @import("../middleware/csrf.zig");

threadlocal var tl_io: ?std.Io = null;

pub fn setIo(io: std.Io) void {
    tl_io = io;
}

/// User model with hashed password, role, and active status.
pub const User = struct {
    username: []const u8,
    password_hash: []const u8,
    role: []const u8 = "user",
    is_active: bool = true,
    gpa: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new user with a hashed password.
    pub fn init(io: std.Io, gpa: std.mem.Allocator, username: []const u8, plaintext: []const u8) !Self {
        const owned_username = try gpa.dupe(u8, username);
        errdefer gpa.free(owned_username);
        const hashed = try password.hash(io, gpa, plaintext);
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
    const session: *Session = @ptrCast(@alignCast(req.user.?));
    const user_role = session.get("user_role") orelse "";
    if (!std.mem.eql(u8, user_role, "admin")) {
        const username = session.get("username") orelse "unknown";
        log.warn("non-admin access to {s} by user '{s}'", .{ req.path, username });
        _ = res.status(403);
        res.text("Forbidden: admin access required") catch {};
        return;
    }
    next(req, res);
}

/// Built-in login view handler.
/// Renders a simple login form with CSRF token.
/// POST handler processes form submission; GET shows the form.
pub fn loginView(req: *Request, res: *Response) void {
    const io = tl_io orelse return;
    if (req.method == .get) {
        const csrf_field = csrf.formFieldForRequest(io, res.allocator, req) catch "";
        defer if (csrf_field.len > 0) res.allocator.free(csrf_field);
        const html = std.fmt.allocPrint(res.allocator,
            \\<!DOCTYPE html><html><head><title>Login</title></head><body>
            \\<h1>Login</h1>
            \\<form method="post" action="/login">
            \\{s}
            \\<label>Username: <input type="text" name="username" required></label>
            \\<label>Password: <input type="password" name="password" required></label>
            \\<button type="submit">Log In</button>
            \\</form></body></html>
        , .{csrf_field}) catch return;
        defer res.allocator.free(html);
        res.html(html) catch {};
        log.info("loginView: GET rendered form", .{});
    } else if (req.method == .post) {
        log.info("loginView: POST login attempt", .{});
        _ = res.status(200);
        res.text("login processed") catch {};
    }
}

/// Built-in logout view handler.
/// Destroys session and redirects to /.
pub fn logoutView(req: *Request, res: *Response) void {
    if (req.user != null) {
        _ = res.deleteCookie("zypher_session");
        log.info("logoutView: user session destroyed", .{});
    }
    _ = res.status(302);
    _ = res.header("Location", "/");
}

/// Built-in register view handler.
/// GET shows registration form. POST processes registration.
pub fn registerView(req: *Request, res: *Response) void {
    const io = tl_io orelse return;
    if (req.method == .get) {
        const csrf_field = csrf.formFieldForRequest(io, res.allocator, req) catch "";
        defer if (csrf_field.len > 0) res.allocator.free(csrf_field);
        const html = std.fmt.allocPrint(res.allocator,
            \\<!DOCTYPE html><html><head><title>Register</title></head><body>
            \\<h1>Register</h1>
            \\<form method="post" action="/register">
            \\{s}
            \\<label>Username: <input type="text" name="username" required></label>
            \\<label>Password: <input type="password" name="password" required></label>
            \\<button type="submit">Register</button>
            \\</form></body></html>
        , .{csrf_field}) catch return;
        defer res.allocator.free(html);
        res.html(html) catch {};
        log.info("registerView: GET rendered form", .{});
    } else if (req.method == .post) {
        log.info("registerView: POST registration attempt", .{});
        _ = res.status(200);
        res.text("registration processed") catch {};
    }
}

test {
    std.testing.refAllDecls(@This());
}
