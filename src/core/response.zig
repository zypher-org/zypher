const std = @import("std");
const log = std.log.scoped(.response);

/// SameSite attribute for cookies.
pub const SameSite = enum {
    Strict,
    Lax,
    None,
};

/// Cookie configuration for Set-Cookie header.
pub const Cookie = struct {
    name: []const u8,
    value: []const u8 = "",
    path: []const u8 = "/",
    domain: ?[]const u8 = null,
    max_age: ?u32 = null,
    secure: bool = false,
    http_only: bool = false,
    same_site: SameSite = .Lax,
};

/// Standard HTTP reason phrases.
fn reasonPhrase(code: u16) ?[]const u8 {
    return switch (code) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        303 => "See Other",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        else => null,
    };
}

fn rawJsonSlice(content: anytype) ?[]const u8 {
    const T = @TypeOf(content);
    return switch (@typeInfo(T)) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => if (ptr.child == u8) content else null,
            .one => switch (@typeInfo(ptr.child)) {
                .array => |arr| if (arr.child == u8) content[0..arr.len] else null,
                else => null,
            },
            else => null,
        },
        .array => |arr| if (arr.child == u8) content[0..] else null,
        else => null,
    };
}

pub const Response = struct {
    status_code: u16 = 200,
    reason_phrase: ?[]const u8 = "OK",
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    // ───────────── Lifecycle ─────────────

    /// Create a new Response with the given allocator.
    pub fn init(gpa: std.mem.Allocator) Response {
        return .{
            .headers = std.StringHashMap([]const u8).init(gpa),
            .allocator = gpa,
        };
    }

    /// Free all owned memory.
    pub fn deinit(self: *Response) void {
        if (self.body) |b| {
            self.allocator.free(b);
        }
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    // ───────────── Mutators (chainable) ─────────────

    /// Set the HTTP status code. Automatically sets the reason phrase for known codes.
    pub fn status(self: *Response, code: u16) *Response {
        self.status_code = code;
        self.reason_phrase = reasonPhrase(code);
        return self;
    }

    /// Set a response header.
    pub fn header(self: *Response, name: []const u8, value: []const u8) *Response {
        if (self.headers.getPtr(name)) |stored_value| {
            const owned_value = self.allocator.dupe(u8, value) catch return self;
            self.allocator.free(stored_value.*);
            stored_value.* = owned_value;
            return self;
        }

        const owned_name = self.allocator.dupe(u8, name) catch return self;
        const owned_value = self.allocator.dupe(u8, value) catch {
            self.allocator.free(owned_name);
            return self;
        };

        self.headers.put(owned_name, owned_value) catch {
            self.allocator.free(owned_name);
            self.allocator.free(owned_value);
            return self;
        };
        return self;
    }

    // ───────────── Body writers ─────────────

    /// Set a plain text body.
    pub fn text(self: *Response, content: []const u8) !void {
        if (self.body) |b| self.allocator.free(b);
        self.body = try self.allocator.dupe(u8, content);
        _ = self.header("Content-Type", "text/plain; charset=utf-8");
    }

    /// Set an HTML body.
    pub fn html(self: *Response, content: []const u8) !void {
        if (self.body) |b| self.allocator.free(b);
        self.body = try self.allocator.dupe(u8, content);
        _ = self.header("Content-Type", "text/html; charset=utf-8");
    }

    /// Set a JSON body.
    ///
    /// Byte strings are treated as already-serialized JSON for backwards
    /// compatibility. Other values are serialized with `std.json`.
    pub fn json(self: *Response, content: anytype) !void {
        if (self.body) |b| self.allocator.free(b);
        if (rawJsonSlice(content)) |raw| {
            self.body = try self.allocator.dupe(u8, raw);
        } else {
            var aw = std.Io.Writer.Allocating.init(self.allocator);
            errdefer aw.deinit();
            try std.json.Stringify.value(content, .{}, &aw.writer);
            var buf = aw.toArrayList();
            self.body = try buf.toOwnedSlice(self.allocator);
        }
        _ = self.header("Content-Type", "application/json");
    }

    /// Set a redirect response with the given status code and Location header.
    pub fn redirect(self: *Response, url: []const u8, code: u16) !void {
        _ = self.status(code);
        _ = self.header("Location", url);
        if (self.body) |b| {
            self.allocator.free(b);
            self.body = null;
        }
    }

    // ───────────── Cookies ─────────────

    /// Add a Set-Cookie header.
    pub fn setCookie(self: *Response, cookie: Cookie) *Response {
        var buf: std.ArrayList(u8) = .empty;
        buf.appendSlice(self.allocator, cookie.name) catch return self;
        buf.appendSlice(self.allocator, "=") catch return self;
        buf.appendSlice(self.allocator, cookie.value) catch return self;
        if (cookie.path.len > 0) {
            buf.appendSlice(self.allocator, "; Path=") catch return self;
            buf.appendSlice(self.allocator, cookie.path) catch return self;
        }
        if (cookie.domain) |d| {
            buf.appendSlice(self.allocator, "; Domain=") catch return self;
            buf.appendSlice(self.allocator, d) catch return self;
        }
        if (cookie.max_age) |ma| {
            buf.appendSlice(self.allocator, "; Max-Age=") catch return self;
            var int_buf: [16]u8 = undefined;
            const str = std.fmt.bufPrint(&int_buf, "{d}", .{ma}) catch return self;
            buf.appendSlice(self.allocator, str) catch return self;
        }
        if (cookie.secure) {
            buf.appendSlice(self.allocator, "; Secure") catch return self;
        }
        if (cookie.http_only) {
            buf.appendSlice(self.allocator, "; HttpOnly") catch return self;
        }
        switch (cookie.same_site) {
            .Strict => buf.appendSlice(self.allocator, "; SameSite=Strict") catch return self,
            .Lax => buf.appendSlice(self.allocator, "; SameSite=Lax") catch return self,
            .None => buf.appendSlice(self.allocator, "; SameSite=None") catch return self,
        }
        const slice = buf.toOwnedSlice(self.allocator) catch return self;
        _ = self.header("Set-Cookie", slice);
        self.allocator.free(slice);
        return self;
    }

    /// Delete a cookie by setting it with Max-Age=0.
    pub fn deleteCookie(self: *Response, name: []const u8) *Response {
        return self.setCookie(.{
            .name = name,
            .value = "",
            .max_age = 0,
            .path = "/",
        });
    }

    // ───────────── Serialisation ─────────────

    /// Serialise the full HTTP response into the provided ArrayList.
    pub fn send(self: *Response, gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        const phrase = self.reason_phrase orelse "";
        try out.appendSlice(gpa, "HTTP/1.1 ");
        var int_buf: [8]u8 = undefined;
        const status_str = try std.fmt.bufPrint(&int_buf, "{d}", .{self.status_code});
        try out.appendSlice(gpa, status_str);
        try out.appendSlice(gpa, " ");
        try out.appendSlice(gpa, phrase);
        try out.appendSlice(gpa, "\r\n");

        try out.appendSlice(gpa, "Content-Length: ");
        var len_buf: [16]u8 = undefined;
        const len = if (self.body) |b| b.len else 0;
        const len_str = try std.fmt.bufPrint(&len_buf, "{d}", .{len});
        try out.appendSlice(gpa, len_str);
        try out.appendSlice(gpa, "\r\n");

        // Write all headers
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try out.appendSlice(gpa, entry.key_ptr.*);
            try out.appendSlice(gpa, ": ");
            try out.appendSlice(gpa, entry.value_ptr.*);
            try out.appendSlice(gpa, "\r\n");
        }

        try out.appendSlice(gpa, "\r\n");

        // Write body
        if (self.body) |b| {
            try out.appendSlice(gpa, b);
        }

        log.info("response sent: {d} {s}, body_len={d}", .{ self.status_code, phrase, if (self.body) |b| b.len else 0 });
    }
};
