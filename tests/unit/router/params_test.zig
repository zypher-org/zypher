/// Unit tests for zypher URL parameter extraction.
const std = @import("std");
const RouteParams = @import("zypher").router.RouteParams;

// ── Basic get ──────────────────────────────────────────────────────

test "RouteParams.get returns value for known param" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "42");
    const val = params.get("id");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("42", val.?);
}

test "RouteParams.get returns null for unknown param" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "42");
    try std.testing.expect(params.get("name") == null);
}

// ── Typed extraction ───────────────────────────────────────────────

test "RouteParams.getAs u64 parses numeric value" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "42");
    const val = try params.getAs(u64, "id");
    try std.testing.expectEqual(@as(u64, 42), val);
}

test "RouteParams.getAs u16 parses numeric value" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("port", "8080");
    const val = try params.getAs(u16, "port");
    try std.testing.expectEqual(@as(u16, 8080), val);
}

test "RouteParams.getAs returns error on non-numeric input" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "abc");
    try std.testing.expectError(error.InvalidCharacter, params.getAs(u64, "id"));
}

test "RouteParams.getAs returns error.MissingParam for unknown param" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    const result = params.getAs(u64, "nonexistent");
    try std.testing.expectError(error.MissingParam, result);
}

// ── Count and iteration ────────────────────────────────────────────

test "RouteParams.count returns number of params" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try std.testing.expectEqual(@as(usize, 0), params.count());
    try params.put("a", "1");
    try std.testing.expectEqual(@as(usize, 1), params.count());
    try params.put("b", "2");
    try std.testing.expectEqual(@as(usize, 2), params.count());
}

test "RouteParams.put overwrites existing key" {
    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "1");
    try params.put("id", "2");
    try std.testing.expectEqual(@as(usize, 1), params.count());
    try std.testing.expectEqualStrings("2", params.get("id").?);
}
