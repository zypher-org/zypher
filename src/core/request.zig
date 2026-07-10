const std = @import("std");
const Method = @import("method.zig").Method;
const RouteParams = @import("../router/params.zig").RouteParams;
const log = std.log.scoped(.request);

pub const Request = struct {
    /// Parsed HTTP Range header value.
    pub const Range = struct {
        /// Start byte position. null for suffix ranges (e.g., bytes=-500).
        start: ?u64,
        /// End byte position. null for open-ended ranges (e.g., bytes=100-).
        end: ?u64,

        /// A satisfied (concrete) byte range computed against a file size.
        pub const Satisfied = struct {
            start: u64,
            end: u64,
            length: u64,
        };

        /// Resolve this range against the given file size, returning the
        /// actual byte range to serve, or null if the range is unsatisfiable.
        pub fn satisfy(self: Range, file_size: u64) ?Satisfied {
            if (self.start) |s| {
                const effective_end = self.end orelse (file_size - 1);
                if (s >= file_size) return null;
                const e = @min(effective_end, file_size - 1);
                return .{ .start = s, .end = e, .length = e - s + 1 };
            } else if (self.end) |suffix| {
                const s = if (suffix >= file_size) 0 else file_size - suffix;
                return .{ .start = s, .end = file_size - 1, .length = file_size - s };
            }
            return null;
        }
    };

    /// Parse an HTTP Range header value (e.g., "bytes=0-999").
    /// Only the first range is parsed; multi-range requests are not supported.
    /// Returns null if the header is absent, malformed, or uses an unsupported unit.
    pub fn parseRangeHeader(header_value: []const u8) ?Range {
        if (header_value.len == 0) return null;
        if (!std.mem.startsWith(u8, header_value, "bytes=")) return null;
        const range_str = header_value["bytes=".len..];
        if (range_str.len == 0) return null;

        const dash = std.mem.indexOfScalar(u8, range_str, '-') orelse return null;

        const start_str = range_str[0..dash];
        const end_str = range_str[dash + 1 ..];

        if (start_str.len > 0 and end_str.len > 0) {
            const start = std.fmt.parseInt(u64, start_str, 10) catch return null;
            const end = std.fmt.parseInt(u64, end_str, 10) catch return null;
            if (end < start) return null;
            return .{ .start = start, .end = end };
        } else if (start_str.len > 0) {
            const start = std.fmt.parseInt(u64, start_str, 10) catch return null;
            return .{ .start = start, .end = null };
        } else if (end_str.len > 0) {
            const suffix = std.fmt.parseInt(u64, end_str, 10) catch return null;
            if (suffix == 0) return null;
            return .{ .start = null, .end = suffix };
        }
        return null;
    }
    pub const FileUpload = struct {
        filename: []const u8,
        content_type: []const u8,
        data: []const u8,

        pub fn deinit(self: *FileUpload, gpa: std.mem.Allocator) void {
            gpa.free(self.filename);
            gpa.free(self.content_type);
            gpa.free(@constCast(self.data));
        }
    };

    pub const MultipartForm = struct {
        fields: std.StringHashMap([]const u8),
        files: std.StringHashMap(FileUpload),
        allocator: std.mem.Allocator,

        pub fn deinit(self: *MultipartForm) void {
            deinitQueryString(&self.fields, self.allocator);
            deinitFiles(&self.files, self.allocator);
        }
    };

    /// Streaming body reader. Present when the body exceeds
    /// `Server.Config.max_inline_body_size`. The handler must call
    /// `read()` until it returns 0.
    pub const BodyStream = struct {
        reader: *std.Io.Reader,
        total_read: usize = 0,

        /// Read the next chunk of the body into `buf`.
        /// Returns the number of bytes written (0 means end of body).
        pub fn read(self: *BodyStream, buf: []u8) !usize {
            const n = try self.reader.readSliceShort(buf);
            self.total_read += n;
            return n;
        }

        /// Skip (read and discard) the remaining body.
        pub fn skip(self: *BodyStream) !void {
            var buf: [4096]u8 = undefined;
            while (true) {
                const n = try self.read(&buf);
                if (n == 0) break;
            }
        }
    };

    /// HTTP method
    method: Method,

    /// Raw request path (e.g. "/users/42")
    path: []const u8,

    /// Query string parameters
    query: std.StringHashMap([]const u8),

    /// HTTP headers
    headers: std.StringHashMap([]const u8),

    /// Raw request body
    body: []const u8,

    /// Whether body was allocated and must be freed in deinit
    body_owned: bool = false,

    /// Whether query/form entries were allocated by decodeUrlEncoded
    query_owned: bool = false,

    /// Uploaded files parsed from multipart/form-data, keyed by field name.
    /// Must be initialized before reading; check files_owned to determine if init'd.
    files: std.StringHashMap(FileUpload) = undefined,

    /// Whether files has been initialized and owns its entries.
    files_owned: bool = false,

    /// Route-extracted URL parameters (populated by Router.dispatch)
    /// .names/.values are undefined when .len == 0 — read only after Router.dispatch sets them
    params: RouteParams = .{ .names = undefined, .values = undefined, .len = 0, .allocator = undefined },

    /// Allocator scoped to this request
    allocator: std.mem.Allocator,

    /// Optional authenticated user (set by auth middleware)
    user: ?*anyopaque = null,

    /// Streaming body reader (set for large uploads instead of buffering in `body`).
    body_stream: ?BodyStream = null,

    // ───────────── Helpers ─────────────

    /// Case-insensitive header lookup.
    pub fn header(self: *const Request, name: []const u8) ?[]const u8 {
        return getHeaderCI(&self.headers, name);
    }

    /// Query parameter lookup.
    pub fn queryParam(self: *const Request, name: []const u8) ?[]const u8 {
        return self.query.get(name);
    }

    /// Form value lookup (same storage as query for URL-encoded bodies).
    pub fn formValue(self: *const Request, name: []const u8) ?[]const u8 {
        return self.query.get(name);
    }

    /// Uploaded file lookup by multipart field name.
    pub fn file(self: *const Request, name: []const u8) ?FileUpload {
        if (!self.files_owned) return null;
        return self.files.get(name);
    }

    /// Parse the HTTP Range header.
    pub fn range(self: *const Request) ?Range {
        const hdr = self.header("Range") orelse return null;
        return parseRangeHeader(hdr);
    }

    /// Cookie lookup.
    pub fn cookie(self: *const Request, name: []const u8) ?[]const u8 {
        const cookie_header = self.header("Cookie") orelse return null;
        var it = std.mem.splitScalar(u8, cookie_header, ';');
        while (it.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " \t");
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |i| {
                const key = std.mem.trim(u8, trimmed[0..i], " \t");
                const value = std.mem.trim(u8, trimmed[i + 1 ..], " \t");
                if (std.mem.eql(u8, key, name)) return value;
            }
        }
        return null;
    }

    /// Free all owned memory.
    pub fn deinit(self: *Request) void {
        self.headers.deinit();
        if (self.query_owned) {
            deinitQueryString(&self.query, self.allocator);
        } else {
            self.query.deinit();
        }
        if (self.body_owned) {
            self.allocator.free(@constCast(self.body));
        }
        if (self.files_owned) {
            deinitFiles(&self.files, self.allocator);
        }
    }

    // ───────────── Static parsing helpers ─────────────

    /// Extract the path portion from a request target (before '?').
    pub fn parsePath(target: []const u8) []const u8 {
        if (std.mem.indexOfScalar(u8, target, '?')) |i| {
            return target[0..i];
        }
        return target;
    }

    /// Parse a query string into a StringHashMap. Caller owns the map.
    /// Use deinitQueryString to free all memory including decoded slices.
    pub fn parseQueryString(gpa: std.mem.Allocator, raw: []const u8) !std.StringHashMap([]const u8) {
        var map = std.StringHashMap([]const u8).init(gpa);
        if (raw.len == 0) return map;
        var it = std.mem.splitScalar(u8, raw, '&');
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
                const key = pair[0..i];
                const value = pair[i + 1 ..];
                const decoded_value = try decodeUrlEncoded(gpa, value);
                const decoded_key = try decodeUrlEncoded(gpa, key);
                try map.put(decoded_key, decoded_value);
            } else {
                const decoded = try decodeUrlEncoded(gpa, pair);
                try map.put(decoded, "");
            }
        }
        return map;
    }

    /// Free all memory from parseQueryString, including decoded key/value slices.
    pub fn deinitQueryString(map: *std.StringHashMap([]const u8), gpa: std.mem.Allocator) void {
        var it = map.iterator();
        while (it.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            if (entry.value_ptr.*.len > 0) {
                gpa.free(entry.value_ptr.*);
            }
        }
        map.deinit();
    }

    /// Parse application/x-www-form-urlencoded body into a map.
    pub fn parseFormUrlEncoded(gpa: std.mem.Allocator, body: []const u8) !std.StringHashMap([]const u8) {
        return parseQueryString(gpa, body);
    }

    /// Parse multipart/form-data into text fields and uploaded files.
    pub fn parseMultipartFormData(gpa: std.mem.Allocator, content_type: []const u8, body: []const u8) !MultipartForm {
        const boundary = multipartBoundary(content_type) orelse return error.MissingMultipartBoundary;
        return parseMultipartFormDataWithBoundary(gpa, boundary, body);
    }

    /// Free all memory from a file upload map.
    pub fn deinitFiles(files: *std.StringHashMap(FileUpload), gpa: std.mem.Allocator) void {
        var it = files.iterator();
        while (it.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            entry.value_ptr.deinit(gpa);
        }
        files.deinit();
    }

    /// Parse cookies from a Cookie header value.
    pub fn parseCookies(gpa: std.mem.Allocator, cookie_header: []const u8) !std.StringHashMap([]const u8) {
        var map = std.StringHashMap([]const u8).init(gpa);
        if (cookie_header.len == 0) return map;
        var it = std.mem.splitSequence(u8, cookie_header, "; ");
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |i| {
                const key = pair[0..i];
                const value = pair[i + 1 ..];
                try map.put(key, value);
            }
        }
        return map;
    }

    /// Case-insensitive header lookup from any header map.
    pub fn getHeaderCI(headers: *const std.StringHashMap([]const u8), name: []const u8) ?[]const u8 {
        var it = headers.iterator();
        while (it.next()) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, name)) {
                return entry.value_ptr.*;
            }
        }
        return null;
    }

    /// Validate body size against a maximum.
    pub fn validateBodySize(body_len: usize, max: usize) !void {
        if (body_len > max) return error.BodyTooLarge;
    }
};

fn multipartBoundary(content_type: []const u8) ?[]const u8 {
    var params = std.mem.splitScalar(u8, content_type, ';');
    _ = params.next() orelse return null;
    while (params.next()) |param| {
        const trimmed = std.mem.trim(u8, param, " \t");
        if (std.mem.startsWith(u8, trimmed, "boundary=")) {
            var value = trimmed["boundary=".len..];
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }
            return value;
        }
    }
    return null;
}

fn parseMultipartFormDataWithBoundary(gpa: std.mem.Allocator, boundary: []const u8, body: []const u8) !Request.MultipartForm {
    var result = Request.MultipartForm{
        .fields = std.StringHashMap([]const u8).init(gpa),
        .files = std.StringHashMap(Request.FileUpload).init(gpa),
        .allocator = gpa,
    };
    errdefer result.deinit();

    const marker = try std.fmt.allocPrint(gpa, "--{s}", .{boundary});
    defer gpa.free(marker);

    var sections = std.mem.splitSequence(u8, body, marker);
    _ = sections.next();
    while (sections.next()) |raw_section| {
        if (std.mem.startsWith(u8, raw_section, "--")) break;

        var section = raw_section;
        if (std.mem.startsWith(u8, section, "\r\n")) section = section[2..];
        if (std.mem.endsWith(u8, section, "\r\n")) section = section[0 .. section.len - 2];
        if (section.len == 0) continue;

        const header_end = std.mem.indexOf(u8, section, "\r\n\r\n") orelse continue;
        const header_block = section[0..header_end];
        const payload = section[header_end + 4 ..];

        var name: ?[]const u8 = null;
        var filename: ?[]const u8 = null;
        var content_type: []const u8 = "";

        var header_lines = std.mem.splitSequence(u8, header_block, "\r\n");
        while (header_lines.next()) |line| {
            if (std.mem.indexOfScalar(u8, line, ':')) |idx| {
                const header_name = std.mem.trim(u8, line[0..idx], " \t");
                const header_value = std.mem.trim(u8, line[idx + 1 ..], " \t");
                if (std.ascii.eqlIgnoreCase(header_name, "Content-Disposition")) {
                    name = dispositionParam(header_value, "name");
                    filename = dispositionParam(header_value, "filename");
                } else if (std.ascii.eqlIgnoreCase(header_name, "Content-Type")) {
                    content_type = header_value;
                }
            }
        }

        const field_name = name orelse continue;
        const owned_key = try gpa.dupe(u8, field_name);
        errdefer gpa.free(owned_key);

        if (filename) |file_name| {
            var upload = Request.FileUpload{
                .filename = try gpa.dupe(u8, file_name),
                .content_type = try gpa.dupe(u8, content_type),
                .data = try gpa.dupe(u8, payload),
            };
            errdefer upload.deinit(gpa);
            if (try result.files.fetchPut(owned_key, upload)) |old| {
                gpa.free(old.key);
                var old_upload = old.value;
                old_upload.deinit(gpa);
            }
        } else {
            const owned_value = try gpa.dupe(u8, payload);
            errdefer gpa.free(owned_value);
            if (try result.fields.fetchPut(owned_key, owned_value)) |old| {
                gpa.free(old.key);
                gpa.free(old.value);
            }
        }
    }

    return result;
}

fn dispositionParam(value: []const u8, param_name: []const u8) ?[]const u8 {
    var parts = std.mem.splitScalar(u8, value, ';');
    _ = parts.next();
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        if (!std.mem.eql(u8, key, param_name)) continue;
        var param_value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        if (param_value.len >= 2 and param_value[0] == '"' and param_value[param_value.len - 1] == '"') {
            param_value = param_value[1 .. param_value.len - 1];
        }
        return param_value;
    }
    return null;
}

/// Decode a URL-encoded string, replacing + with space and %XX with bytes.
fn decodeUrlEncoded(gpa: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '+') {
            try buf.append(gpa, ' ');
        } else if (raw[i] == '%' and i + 2 < raw.len) {
            const byte = std.fmt.parseInt(u8, raw[i + 1 .. i + 3], 16) catch return error.InvalidPercentEncoding;
            try buf.append(gpa, byte);
            i += 2;
        } else {
            try buf.append(gpa, raw[i]);
        }
    }
    return buf.toOwnedSlice(gpa);
}

/// Percent-encode a string for use in a URI component.
/// Unreserved characters (A-Z, a-z, 0-9, -, _, ., ~) are left as-is.
/// Spaces are encoded as %20. All other bytes are percent-encoded.
pub fn urlEncode(gpa: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    for (input) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => try buf.append(gpa, c),
            ' ' => try buf.appendSlice(gpa, "%20"),
            else => {
                try buf.append(gpa, '%');
                try buf.append(gpa, std.fmt.digitToChar(c >> 4, .upper));
                try buf.append(gpa, std.fmt.digitToChar(c & 0xf, .upper));
            },
        }
    }
    return buf.toOwnedSlice(gpa);
}

/// Decode a percent-encoded URI component.
/// This does NOT convert + to space (that is form-encoding specific).
/// Returns `error.InvalidPercentEncoding` on malformed %-sequences.
pub fn urlDecode(gpa: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const byte = std.fmt.parseInt(u8, input[i + 1 .. i + 3], 16) catch return error.InvalidPercentEncoding;
            try buf.append(gpa, byte);
            i += 3;
        } else {
            try buf.append(gpa, input[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice(gpa);
}
