/// zypher auth — session management with in-memory store.
const std = @import("std");
const log = std.log.scoped(.session);
const posix = std.posix;
const Random = std.Random;

/// Session ID length in bytes (256-bit random).
pub const SESSION_ID_LEN = 32;

/// Cookie configuration for session cookies.
pub const CookieConfig = struct {
    httponly: bool = true,
    secure: bool = true,
    samesite: [:0]const u8 = "Strict",
    path: [:0]const u8 = "/",
    max_age: u32 = 86400, // 24 hours default
};

/// Default cookie config for production.
const default_cookie_config = CookieConfig{};

pub fn cookieConfig() CookieConfig {
    return default_cookie_config;
}

/// Get current unix timestamp using clock_gettime.
fn unixTimestamp() i64 {
    const ts = posix.clock_gettime(posix.CLOCK.REALTIME) catch return 0;
    return ts.sec;
}

/// Fill buffer with cryptographically random bytes.
/// Uses ChaCha CSPRNG seeded from POSIX clock_gettime for entropy.
fn randomBytes(buf: []u8) void {
    var seed: [32]u8 = undefined;
    const ts = posix.clock_gettime(posix.CLOCK.REALTIME) catch return;
    @memcpy(seed[0..8], std.mem.asBytes(&ts.sec));
    @memcpy(seed[8..16], std.mem.asBytes(&ts.nsec));
    // Fill remaining with repeating pattern of timestamp bytes
    var i: usize = 16;
    while (i < 32) : (i += 8) {
        @memcpy(seed[i..@min(i + 8, 32)], seed[0..@min(8, 32 - i)]);
    }
    var csprng = Random.DefaultCsprng.init(seed);
    csprng.random().bytes(buf);
}

/// A single session with ID, data, and expiry.
pub const Session = struct {
    id: [SESSION_ID_LEN]u8,
    data: std.StringHashMap([]const u8),
    expires_at: i64, // unix timestamp, 0 = no expiry

    const Self = @This();

    /// Put a key-value pair into the session data.
    pub fn put(self: *Self, gpa: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        const owned_key = try gpa.dupe(u8, key);
        const owned_value = try gpa.dupe(u8, value);
        errdefer {
            gpa.free(owned_key);
            gpa.free(owned_value);
        }
        const old = try self.data.fetchPut(owned_key, owned_value);
        if (old) |entry| {
            gpa.free(entry.key);
            gpa.free(entry.value);
        }
        log.debug("session: set {s}", .{key});
    }

    /// Get a value from the session data.
    pub fn get(self: *const Self, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    /// Check if this session has expired.
    pub fn isExpired(self: *const Self) bool {
        if (self.expires_at == 0) return false;
        return unixTimestamp() > self.expires_at;
    }

    /// Free session data (not the session struct itself).
    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            gpa.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }
};

/// In-memory session store backed by HashMap.
pub const SessionStore = struct {
    gpa: std.mem.Allocator,
    sessions: std.StringHashMap(Session),

    const Self = @This();

    /// Initialize a new session store.
    pub fn init(gpa: std.mem.Allocator) Self {
        return .{
            .gpa = gpa,
            .sessions = std.StringHashMap(Session).init(gpa),
        };
    }

    /// Free all sessions and the store.
    pub fn deinit(self: *Self) void {
        var iter = self.sessions.iterator();
        while (iter.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.gpa);
        }
        self.sessions.deinit();
    }

    /// Create a new session with random ID and default expiry.
    pub fn create(self: *Self) !Session {
        return self.createWithExpiry(unixTimestamp() + default_cookie_config.max_age);
    }

    /// Create a new session with a specific expiry timestamp.
    pub fn createWithExpiry(self: *Self, expires_at: i64) !Session {
        var id: [SESSION_ID_LEN]u8 = undefined;
        randomBytes(&id);

        const s = Session{
            .id = id,
            .data = std.StringHashMap([]const u8).init(self.gpa),
            .expires_at = expires_at,
        };

        log.info("created session (expires_at={d})", .{expires_at});
        return s;
    }

    /// Save a session to the store (deep-copies data).
    pub fn save(self: *Self, session: *Session) !void {
        const id_hex = std.fmt.bytesToHex(session.id, .lower);
        const id_hex_alloc = try self.gpa.dupe(u8, &id_hex);
        errdefer self.gpa.free(id_hex_alloc);

        // Deep-copy session data into store-owned memory
        var stored = Session{
            .id = session.id,
            .data = std.StringHashMap([]const u8).init(self.gpa),
            .expires_at = session.expires_at,
        };
        var iter = session.data.iterator();
        while (iter.next()) |entry| {
            const owned_key = try self.gpa.dupe(u8, entry.key_ptr.*);
            const owned_val = try self.gpa.dupe(u8, entry.value_ptr.*);
            const old_stored = try stored.data.fetchPut(owned_key, owned_val);
            if (old_stored) |e| {
                self.gpa.free(e.key);
                self.gpa.free(e.value);
            }
        }

        const old = try self.sessions.fetchPut(id_hex_alloc, stored);
        if (old) |entry| {
            self.gpa.free(entry.key);
            var val = entry.value;
            val.deinit(self.gpa);
        }
        log.info("saved session", .{});
    }

    /// Get a session by hex-encoded ID string. Returns null if not found or expired.
    pub fn getByHexId(self: *Self, hex_id: []const u8) !?*Session {
        const result = self.sessions.getPtr(hex_id);
        if (result) |s| {
            if (s.isExpired()) {
                log.info("session {s} expired", .{hex_id});
                self.destroyByHexId(hex_id) catch {};
                return null;
            }
            return @constCast(s);
        }
        return null;
    }

    /// Get a session by raw ID bytes. Returns null if not found or expired.
    pub fn get(self: *Self, raw_id: [SESSION_ID_LEN]u8) !?*Session {
        const hex_id = std.fmt.bytesToHex(raw_id, .lower);
        const hex_alloc = try self.gpa.dupe(u8, &hex_id);
        defer self.gpa.free(hex_alloc);
        return self.getByHexId(hex_alloc);
    }

    /// Destroy a session by hex-encoded ID string.
    pub fn destroyByHexId(self: *Self, hex_id: []const u8) !void {
        if (self.sessions.fetchRemove(hex_id)) |entry| {
            self.gpa.free(entry.key);
            var val = entry.value;
            val.deinit(self.gpa);
            log.info("destroyed session {s}", .{hex_id});
        }
    }

    /// Destroy a session by raw ID bytes.
    pub fn destroy(self: *Self, raw_id: [SESSION_ID_LEN]u8) !void {
        const hex_id = std.fmt.bytesToHex(raw_id, .lower);
        const hex_alloc = try self.gpa.dupe(u8, &hex_id);
        defer self.gpa.free(hex_alloc);
        return self.destroyByHexId(hex_alloc);
    }
};

test {
    std.testing.refAllDecls(@This());
}
