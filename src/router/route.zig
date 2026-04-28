/// zypher Route — comptime route definition and runtime path matching.
const std = @import("std");
const Method = @import("../core/method.zig").Method;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const RouteParams = @import("params.zig").RouteParams;
const log = std.log.scoped(.route);

pub const Route = struct {
    method: Method,
    pattern: []const u8,
    handler: *const fn (*Request, *Response) void,

    /// Create a route at comptime.
    pub fn init(m: Method, pat: []const u8, h: *const fn (*Request, *Response) void) Route {
        return .{ .method = m, .pattern = pat, .handler = h };
    }

    /// Validate a path pattern at comptime. Returns error on invalid patterns.
    pub fn validatePattern(pattern: []const u8) !void {
        if (pattern.len == 0) return error.InvalidPattern;
        if (pattern[0] != '/') return error.InvalidPattern;

        var seen_names: [RouteParams.max_params][]const u8 = undefined;
        var seen_count: usize = 0;
        var after_wildcard = false;

        var it = std.mem.splitScalar(u8, pattern, '/');
        // Skip the first empty segment (pattern starts with /)
        _ = it.next();
        while (it.next()) |segment| {
            if (segment.len == 0) continue;
            if (after_wildcard) return error.InvalidPattern;

            if (segment[0] == '*') {
                after_wildcard = true;
                continue;
            }

            if (segment[0] == ':') {
                const name = segment[1..];
                for (seen_names[0..seen_count]) |existing| {
                    if (std.mem.eql(u8, existing, name)) return error.DuplicateParam;
                }
                seen_names[seen_count] = name;
                seen_count += 1;
            }
        }
    }

    /// Match a pattern against an actual path, extracting params.
    /// Returns true if matched, false otherwise.
    /// On match, params are populated with extracted values (slices into `actual`).
    pub fn matchPath(pattern: []const u8, actual: []const u8, params: *RouteParams) bool {
        params.reset();

        var pat_it = std.mem.splitScalar(u8, pattern, '/');
        var act_it = std.mem.splitScalar(u8, actual, '/');

        // Skip first empty segments (both start with /)
        _ = pat_it.next();
        _ = act_it.next();

        while (true) {
            const pat_seg = pat_it.next() orelse "";
            const act_seg = act_it.next() orelse "";

            // Both empty — end of both paths, match
            if (pat_seg.len == 0 and act_seg.len == 0) return true;

            // Pattern ended but actual continues — no match
            if (pat_seg.len == 0) return false;

            // Wildcard — consume the rest of the actual path
            if (pat_seg[0] == '*') {
                // No more actual segments — check if path ends with /
                if (act_seg.len == 0) {
                    // Trailing slash produces an empty final segment
                    if (actual.len > 0 and actual[actual.len - 1] == '/') {
                        params.put("*", "") catch return false;
                        return true;
                    }
                    return false;
                }
                // Reconstruct remaining path from current position
                const wildcard_val = remainingPath(actual, act_seg);
                params.put("*", wildcard_val) catch return false;
                return true;
            }

            // Actual ended but pattern continues — no match
            if (act_seg.len == 0) return false;

            // Named param — extract value
            if (pat_seg[0] == ':') {
                const name = pat_seg[1..];
                params.put(name, act_seg) catch return false;
                continue;
            }

            // Static segment — must match exactly
            if (!std.mem.eql(u8, pat_seg, act_seg)) return false;
        }
        return false;
    }

    /// Compute the remaining path starting from the current segment position.
    /// Returns a slice into `path` from the segment onward.
    fn remainingPath(path: []const u8, current_segment: []const u8) []const u8 {
        if (current_segment.len == 0) return "";
        // Find where current_segment starts in path
        const idx = std.mem.indexOf(u8, path, current_segment) orelse return "";
        return path[idx..];
    }
};

test {
    std.testing.refAllDecls(@This());
}
