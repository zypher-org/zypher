const std = @import("std");
const validators = @import("zypher").forms.validators;

const required = validators.required;
const minLength = validators.minLength;
const maxLength = validators.maxLength;
const email = validators.email;
const url = validators.url;
const min = validators.min;
const max = validators.max;
const choices = validators.choices;
const custom = validators.custom;

// ── required ──────────────────────────────────────────────────────────────

test "validators: required rejects empty string" {
    try std.testing.expect(required("") != null);
    try std.testing.expect(required("hello") == null);
}

test "validators: required rejects null" {
    const maybe: ?[]const u8 = null;
    try std.testing.expect(requiredOptional(maybe) != null);
    const present: ?[]const u8 = "value";
    try std.testing.expect(requiredOptional(present) == null);
}

const requiredOptional = validators.requiredOptional;

// ── minLength / maxLength ─────────────────────────────────────────────────

test "validators: minLength rejects strings shorter than n" {
    const v = minLength(3);
    try std.testing.expect(v("ab") != null);
    try std.testing.expect(v("abc") == null);
    try std.testing.expect(v("abcd") == null);
}

test "validators: maxLength rejects strings longer than n" {
    const v = maxLength(5);
    try std.testing.expect(v("abcdef") != null);
    try std.testing.expect(v("abcde") == null);
    try std.testing.expect(v("abc") == null);
}

// ── email ─────────────────────────────────────────────────────────────────

test "validators: email accepts valid addresses" {
    try std.testing.expect(email("user@example.com") == null);
    try std.testing.expect(email("a@b.co") == null);
    try std.testing.expect(email("user+tag@domain.org") == null);
}

test "validators: email rejects invalid addresses" {
    try std.testing.expect(email("") != null);
    try std.testing.expect(email("no-at-sign") != null);
    try std.testing.expect(email("@no-local.com") != null);
    try std.testing.expect(email("no-domain@") != null);
    try std.testing.expect(email("user@.com") != null);
}

// ── url ───────────────────────────────────────────────────────────────────

test "validators: url accepts valid URLs" {
    try std.testing.expect(url("http://example.com") == null);
    try std.testing.expect(url("https://example.com/path?q=1") == null);
    try std.testing.expect(url("https://sub.domain.org") == null);
}

test "validators: url rejects invalid URLs" {
    try std.testing.expect(url("") != null);
    try std.testing.expect(url("ftp://example.com") != null);
    try std.testing.expect(url("example.com") != null);
    try std.testing.expect(url("http://") != null);
}

// ── min / max ──────────────────────────────────────────────────────────────

test "validators: min rejects values below threshold" {
    const v = min(i64, 10);
    try std.testing.expect(v(5) != null);
    try std.testing.expect(v(10) == null);
    try std.testing.expect(v(15) == null);
}

test "validators: max rejects values above threshold" {
    const v = max(i64, 100);
    try std.testing.expect(v(150) != null);
    try std.testing.expect(v(100) == null);
    try std.testing.expect(v(50) == null);
}

// ── choices ───────────────────────────────────────────────────────────────

test "validators: choices accepts values in the set" {
    const valid = [_][]const u8{ "red", "green", "blue" };
    const v = choices(&valid);
    try std.testing.expect(v("red") == null);
    try std.testing.expect(v("green") == null);
    try std.testing.expect(v("yellow") != null);
}

// ── custom ────────────────────────────────────────────────────────────────

test "validators: custom validator with fn pointer" {
    const evenOnly = struct {
        fn validate(val: i64) ?[]const u8 {
            if (@rem(val, 2) != 0) return "must be even";
            return null;
        }
    }.validate;
    const v = custom(i64, evenOnly);
    try std.testing.expect(v(2) == null);
    try std.testing.expect(v(3) != null);
}
