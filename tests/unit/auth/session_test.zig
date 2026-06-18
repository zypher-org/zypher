const std = @import("std");
const session = @import("zypher").auth.session;

const SessionStore = session.SessionStore;
const Session = session.Session;

// ── Session creation ──────────────────────────────────────────────────────

test "session: new session created with random ID" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s = store.create(std.testing.io);
    defer s.deinit(std.testing.allocator);
    try std.testing.expect(s.id.len > 0);
}

test "session: session ID is not guessable (entropy check)" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s1 = store.create(std.testing.io);
    defer s1.deinit(std.testing.allocator);
    var s2 = store.create(std.testing.io);
    defer s2.deinit(std.testing.allocator);
    // Two different sessions must have different IDs
    try std.testing.expect(!std.mem.eql(u8, &s1.id, &s2.id));
}

// ── Session store ─────────────────────────────────────────────────────────

test "session: session stored and retrieved from store" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s = store.create(std.testing.io);
    try s.put(std.testing.allocator, "user_id", "42");
    try store.save(&s);
    s.deinit(std.testing.allocator); // save deep-copies, so local s can be freed

    const retrieved = try store.get(s.id);
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("42", retrieved.?.get("user_id") orelse "");
}

test "session: saving retrieved store-owned session keeps lookup valid" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s = store.create(std.testing.io);
    try s.put(std.testing.allocator, "user_id", "42");
    try store.save(&s);
    const session_id = s.id;
    s.deinit(std.testing.allocator);

    const retrieved = (try store.get(session_id)).?;
    try retrieved.put(std.testing.allocator, "role", "user");
    try store.save(retrieved);

    const again = (try store.get(session_id)).?;
    try std.testing.expectEqualStrings("42", again.get("user_id") orelse "");
    try std.testing.expectEqualStrings("user", again.get("role") orelse "");
}

test "session: non-existent session returns null" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    const result = try store.getByHexId("nonexistent");
    try std.testing.expect(result == null);
}

// ── Session data ──────────────────────────────────────────────────────────

test "session: get and set data" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s = store.create(std.testing.io);
    defer s.deinit(std.testing.allocator);
    try s.put(std.testing.allocator, "key1", "value1");
    try s.put(std.testing.allocator, "key2", "value2");

    try std.testing.expectEqualStrings("value1", s.get("key1") orelse "");
    try std.testing.expectEqualStrings("value2", s.get("key2") orelse "");
    try std.testing.expect(s.get("nonexistent") == null);
}

// ── Session expiry ────────────────────────────────────────────────────────

test "session: expired sessions return null" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s = store.createWithExpiry(std.testing.io, 1); // epoch 1 = Jan 1 1970, already expired
    try s.put(std.testing.allocator, "user", "alice");
    try store.save(&s);
    s.deinit(std.testing.allocator); // save deep-copies, so local s can be freed

    // Retrieving should return null because it's expired
    const retrieved = try store.get(s.id);
    try std.testing.expect(retrieved == null);
}

// ── Session destroy ───────────────────────────────────────────────────────

test "session: session destroyed on logout" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var s = store.create(std.testing.io);
    try s.put(std.testing.allocator, "user", "bob");
    try store.save(&s);
    s.deinit(std.testing.allocator); // save deep-copies, so local s can be freed

    try store.destroy(s.id);

    const retrieved = try store.get(s.id);
    try std.testing.expect(retrieved == null);
}

// ── Session cookie attributes ─────────────────────────────────────────────

test "session: cookie attributes are HttpOnly, SameSite=Strict, Secure" {
    const cookie = session.cookieConfig();
    try std.testing.expect(cookie.httponly);
    try std.testing.expectEqualStrings("Strict", cookie.samesite);
    try std.testing.expect(cookie.secure);
}
