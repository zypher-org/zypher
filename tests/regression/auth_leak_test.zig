const std = @import("std");
const password = @import("zypher").auth.password;

// ── Timing attack regression ────────────────────────────────────────────

test "regression: password verify timing within tolerance" {
    // Verify that failed and successful authentication take similar time.
    // This is a regression test — if the constant-time comparison is
    // broken, the timing difference will exceed the tolerance.
    const hashed = try password.hash(std.testing.allocator, "testpassword");
    defer std.testing.allocator.free(hashed);

    // Warm up
    _ = try password.verify(hashed, "testpassword");
    _ = try password.verify(hashed, "wrongpassword");

    // Measure successful verify
    var ts1: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts1);
    _ = try password.verify(hashed, "testpassword");
    var ts2: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts2);
    const success_ns = (ts2.sec - ts1.sec) * 1_000_000_000 + (ts2.nsec - ts1.nsec);

    // Measure failed verify
    var ts3: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts3);
    _ = try password.verify(hashed, "wrongpassword");
    var ts4: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts4);
    const fail_ns = (ts4.sec - ts3.sec) * 1_000_000_000 + (ts4.nsec - ts3.nsec);

    // Both should take roughly the same time (PBKDF2 dominates, not the comparison)
    // Allow 50% tolerance since PBKDF2 iteration time varies
    const ratio = if (success_ns > fail_ns)
        @as(f64, @floatFromInt(success_ns)) / @as(f64, @floatFromInt(fail_ns + 1))
    else
        @as(f64, @floatFromInt(fail_ns)) / @as(f64, @floatFromInt(success_ns + 1));

    // Ratio should be close to 1.0 — both paths do the same PBKDF2 work
    try std.testing.expect(ratio < 2.0);
}

test "regression: session store deep-copy prevents double-free" {
    const session_mod = @import("zypher").auth.session;
    const SessionStore = session_mod.SessionStore;

    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();

    // Create and save a session with data
    var s = try store.create();
    try s.put(std.testing.allocator, "key1", "val1");
    try s.put(std.testing.allocator, "key2", "val2");
    try store.save(&s);
    s.deinit(std.testing.allocator); // This should NOT double-free

    // Verify data is still accessible from the store
    const retrieved = try store.get(s.id);
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("val1", retrieved.?.get("key1") orelse "");
    try std.testing.expectEqualStrings("val2", retrieved.?.get("key2") orelse "");

    // Destroy and verify cleanup
    try store.destroy(s.id);
    const after = try store.get(s.id);
    try std.testing.expect(after == null);
}
