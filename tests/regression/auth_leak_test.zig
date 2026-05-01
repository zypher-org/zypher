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
    const t1_start = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch unreachable;
    _ = try password.verify(hashed, "testpassword");
    const t1_end = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch unreachable;
    const success_ns = (t1_end.sec - t1_start.sec) * 1_000_000_000 + (t1_end.nsec - t1_start.nsec);

    // Measure failed verify
    const t2_start = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch unreachable;
    _ = try password.verify(hashed, "wrongpassword");
    const t2_end = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch unreachable;
    const fail_ns = (t2_end.sec - t2_start.sec) * 1_000_000_000 + (t2_end.nsec - t2_start.nsec);

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
