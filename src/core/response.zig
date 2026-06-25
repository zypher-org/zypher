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
        206 => "Partial Content",
        301 => "Moved Permanently",
        302 => "Found",
        303 => "See Other",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        416 => "Range Not Satisfiable",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        else => null,
    };
}

/// Reject or sanitize CR/LF in header values to prevent header injection.
fn sanitizeHeaderValue(value: []const u8) bool {
    for (value) |c| {
        if (c == '\r' or c == '\n') return false;
    }
    return true;
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

/// File body to be read and written via std.Io.File.
pub const FileBody = struct {
    handle: std.Io.File.Handle,
    size: usize,
};

pub const Response = struct {
    status_code: u16 = 200,
    reason_phrase: ?[]const u8 = "OK",
    headers: std.StringHashMap([]const u8),
    set_cookie_headers: std.ArrayList([]const u8) = .empty,
    body: ?[]const u8 = null,
    use_chunked: bool = false,
    allocator: std.mem.Allocator,
    /// When set, the response body is streamed directly from this file
    /// descriptor instead of from `body`. The caller is responsible for
    /// closing the fd after the response has been sent.
    file_body: ?FileBody = null,

    // ───────────── Lifecycle ─────────────

    /// Create a new Response with the given allocator.
    pub fn init(gpa: std.mem.Allocator) Response {
        return .{
            .headers = std.StringHashMap([]const u8).init(gpa),
            .allocator = gpa,
        };
    }

    /// Use a file handle as the response body, streaming its contents
    /// to the socket. The caller retains ownership of `handle` and
    /// must close it after the response has been sent.
    pub fn setFileBody(self: *Response, handle: std.Io.File.Handle, size: usize) !void {
        if (self.body) |b| self.allocator.free(b);
        self.body = null;
        self.file_body = .{ .handle = handle, .size = size };
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
        for (self.set_cookie_headers.items) |cookie| {
            self.allocator.free(cookie);
        }
        self.set_cookie_headers.deinit(self.allocator);
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
        if (!sanitizeHeaderValue(name) or !sanitizeHeaderValue(value)) return self;
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

    /// Add a raw Set-Cookie header value. Multiple Set-Cookie headers are preserved.
    pub fn addSetCookie(self: *Response, value: []const u8) *Response {
        if (!sanitizeHeaderValue(value)) return self;
        const owned_value = self.allocator.dupe(u8, value) catch return self;
        self.set_cookie_headers.append(self.allocator, owned_value) catch {
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

    /// Set a streaming (chunked) response.
    /// The body is sent as the initial chunk data; set Transfer-Encoding: chunked.
    pub fn stream(self: *Response, content: []const u8) !void {
        if (self.body) |b| self.allocator.free(b);
        self.body = try self.allocator.dupe(u8, content);
        self.use_chunked = true;
        _ = self.header("Transfer-Encoding", "chunked");
        _ = self.header("Content-Type", "text/plain; charset=utf-8");
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
        defer buf.deinit(self.allocator);
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
        _ = self.addSetCookie(buf.items);
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

    /// Serialise the response status line and headers into the provided writer.
    pub fn sendHeaders(self: *Response, w: *std.Io.Writer) !void {
        const phrase = self.reason_phrase orelse "";
        try w.writeAll("HTTP/1.1 ");
        var int_buf: [8]u8 = undefined;
        const status_str = try std.fmt.bufPrint(&int_buf, "{d}", .{self.status_code});
        try w.writeAll(status_str);
        try w.writeAll(" ");
        try w.writeAll(phrase);
        try w.writeAll("\r\n");

        if (!self.use_chunked) {
            try w.writeAll("Content-Length: ");
            var len_buf: [16]u8 = undefined;
            const len = if (self.file_body) |fb|
                fb.size
            else if (self.body) |b|
                b.len
            else
                0;
            const len_str = try std.fmt.bufPrint(&len_buf, "{d}", .{len});
            try w.writeAll(len_str);
            try w.writeAll("\r\n");
        }

        // Write all headers
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try w.writeAll(entry.key_ptr.*);
            try w.writeAll(": ");
            try w.writeAll(entry.value_ptr.*);
            try w.writeAll("\r\n");
        }
        for (self.set_cookie_headers.items) |cookie| {
            try w.writeAll("Set-Cookie: ");
            try w.writeAll(cookie);
            try w.writeAll("\r\n");
        }

        try w.writeAll("\r\n");
    }

    /// Serialise the full HTTP response into the provided writer.
    /// If `file_body` is set, the file content is read in chunks and written.
    pub fn send(self: *Response, io: std.Io, w: *std.Io.Writer) !void {
        try self.sendHeaders(w);

        const phrase = self.reason_phrase orelse "";

        // Write body
        if (self.body) |b| {
            try w.writeAll(b);
        } else if (self.file_body) |fb| {
            // Stream file content in chunks
            var buf: [8192]u8 = undefined;
            var remaining: usize = fb.size;
            const file = std.Io.File{ .handle = fb.handle, .flags = .{ .nonblocking = false } };
            while (remaining > 0) {
                const to_read = @min(buf.len, remaining);
                var data: [1][]u8 = .{buf[0..to_read]};
                const n = try std.Io.File.readStreaming(file, io, &data);
                if (n == 0) break;
                try w.writeAll(buf[0..n]);
                remaining -= n;
            }
        }

        log.info("response sent: {d} {s}, body_len={d}", .{ self.status_code, phrase, if (self.file_body) |fb| fb.size else if (self.body) |b| b.len else 0 });
    }
};
