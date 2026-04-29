const std = @import("std");
const filters = @import("zypher").template.filters;
const renderer = @import("zypher").template.renderer;

const Value = renderer.Value;
const FilterFn = filters.FilterFn;

test "filters: upper converts string to uppercase" {
    const gpa = std.testing.allocator;
    var result = try filters.apply(gpa, "upper", Value{ .string = "hello" });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("HELLO", result.value.string);
}

test "filters: lower converts string to lowercase" {
    const gpa = std.testing.allocator;
    var result = try filters.apply(gpa, "lower", Value{ .string = "HELLO" });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("hello", result.value.string);
}

test "filters: capitalize converts first char to upper" {
    const gpa = std.testing.allocator;
    var result = try filters.apply(gpa, "capitalize", Value{ .string = "hello world" });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("Hello world", result.value.string);
}

test "filters: trim removes leading/trailing whitespace" {
    const gpa = std.testing.allocator;
    var result = try filters.apply(gpa, "trim", Value{ .string = "  hello  " });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("hello", result.value.string);
}

test "filters: length returns string length as int" {
    const gpa = std.testing.allocator;
    var result = try filters.apply(gpa, "length", Value{ .string = "hello" });
    defer result.deinit(gpa);
    try std.testing.expectEqual(Value{ .int = 5 }, result.value);
}

test "filters: length returns list length as int" {
    const gpa = std.testing.allocator;
    const items = &[_]Value{ .{ .string = "a" }, .{ .string = "b" } };
    var result = try filters.apply(gpa, "length", Value{ .list = items });
    defer result.deinit(gpa);
    try std.testing.expectEqual(Value{ .int = 2 }, result.value);
}

test "filters: default returns value when non-null" {
    const gpa = std.testing.allocator;
    var result = try filters.applyDefault(gpa, Value{ .string = "actual" }, Value{ .string = "fallback" });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("actual", result.value.string);
}

test "filters: default returns fallback when null" {
    const gpa = std.testing.allocator;
    var result = try filters.applyDefault(gpa, Value.null_val, Value{ .string = "fallback" });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("fallback", result.value.string);
}

test "filters: unknown filter passes value through unchanged" {
    const gpa = std.testing.allocator;
    var result = try filters.apply(gpa, "nonexistent", Value{ .string = "test" });
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("test", result.value.string);
}

test "filters: join concatenates list with separator" {
    const gpa = std.testing.allocator;
    const items = &[_]Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    var result = try filters.applyWithArg(gpa, "join", Value{ .list = items }, ", ");
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("a, b, c", result.value.string);
}
