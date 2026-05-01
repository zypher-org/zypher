/// zypher forms — field validators.
/// Each validator returns null on success, or an error message string on failure.
const std = @import("std");

pub const ValidatorResult = ?[]const u8;
pub const StringValidator = fn ([]const u8) ValidatorResult;
pub const IntValidator = fn (i64) ValidatorResult;

// ── required ──────────────────────────────────────────────────────────────

pub fn required(value: []const u8) ValidatorResult {
    if (value.len == 0) return "this field is required";
    return null;
}

pub fn requiredOptional(value: ?[]const u8) ValidatorResult {
    if (value == null) return "this field is required";
    if (value.?.len == 0) return "this field is required";
    return null;
}

// ── minLength / maxLength ─────────────────────────────────────────────────

pub fn minLength(comptime n: usize) fn ([]const u8) ValidatorResult {
    return struct {
        fn validate(value: []const u8) ValidatorResult {
            if (value.len < n) return "must be at least {d} characters";
            return null;
        }
    }.validate;
}

pub fn maxLength(comptime n: usize) fn ([]const u8) ValidatorResult {
    return struct {
        fn validate(value: []const u8) ValidatorResult {
            if (value.len > n) return "must be at most {d} characters";
            return null;
        }
    }.validate;
}

// ── email ─────────────────────────────────────────────────────────────────

pub fn email(value: []const u8) ValidatorResult {
    if (value.len == 0) return "invalid email address";
    // Must contain exactly one @
    var at_count: usize = 0;
    var at_pos: usize = 0;
    for (value, 0..) |ch, i| {
        if (ch == '@') {
            at_count += 1;
            at_pos = i;
        }
    }
    if (at_count != 1) return "invalid email address";
    // Local part must not be empty
    if (at_pos == 0) return "invalid email address";
    // Domain part must not be empty and must contain a dot
    const domain = value[at_pos + 1 ..];
    if (domain.len == 0) return "invalid email address";
    if (domain[0] == '.') return "invalid email address";
    var has_dot = false;
    for (domain) |ch| {
        if (ch == '.') has_dot = true;
    }
    if (!has_dot) return "invalid email address";
    return null;
}

// ── url ───────────────────────────────────────────────────────────────────

pub fn url(value: []const u8) ValidatorResult {
    if (value.len == 0) return "invalid URL";
    // Must start with http:// or https://
    const http_prefix = "http://";
    const https_prefix = "https://";
    const is_http = value.len > http_prefix.len and std.mem.startsWith(u8, value, http_prefix);
    const is_https = value.len > https_prefix.len and std.mem.startsWith(u8, value, https_prefix);
    if (!is_http and !is_https) return "invalid URL";
    const prefix_len: usize = if (is_https) https_prefix.len else http_prefix.len;
    const host_part = value[prefix_len..];
    if (host_part.len == 0) return "invalid URL";
    // Must have at least one character before any / or ?
    var host_end: usize = host_part.len;
    for (host_part, 0..) |ch, i| {
        if (ch == '/' or ch == '?' or ch == '#') {
            host_end = i;
            break;
        }
    }
    const host = host_part[0..host_end];
    if (host.len == 0) return "invalid URL";
    // Host must contain a dot (basic check)
    var has_dot = false;
    for (host) |ch| {
        if (ch == '.') has_dot = true;
    }
    if (!has_dot) return "invalid URL";
    return null;
}

// ── min / max ──────────────────────────────────────────────────────────────

pub fn min(comptime T: type, comptime threshold: T) fn (T) ValidatorResult {
    return struct {
        fn validate(value: T) ValidatorResult {
            if (value < threshold) return "value is too small";
            return null;
        }
    }.validate;
}

pub fn max(comptime T: type, comptime threshold: T) fn (T) ValidatorResult {
    return struct {
        fn validate(value: T) ValidatorResult {
            if (value > threshold) return "value is too large";
            return null;
        }
    }.validate;
}

// ── choices ───────────────────────────────────────────────────────────────

pub fn choices(valid_values: []const []const u8) fn ([]const u8) ValidatorResult {
    return struct {
        fn validate(value: []const u8) ValidatorResult {
            for (valid_values) |v| {
                if (std.mem.eql(u8, value, v)) return null;
            }
            return "invalid choice";
        }
    }.validate;
}

// ── custom ────────────────────────────────────────────────────────────────

pub fn custom(comptime T: type, comptime validate_fn: fn (T) ValidatorResult) fn (T) ValidatorResult {
    return validate_fn;
}

test {
    std.testing.refAllDecls(@This());
}
