/// zypher auth — password hashing and verification.
/// Uses PBKDF2-HMAC-SHA256 with random salt.
const std = @import("std");
const log = std.log.scoped(.password);
const pbkdf2 = std.crypto.pwhash.pbkdf2;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Random = std.Random;

/// Hash output length in bytes.
const HASH_LEN = 32;
/// Salt length in bytes.
const SALT_LEN = 16;
/// PBKDF2 iteration count.
const ITERATIONS: u32 = 100_000;

/// Error set for password operations.
pub const PasswordError = error{
    InvalidHashFormat,
    HashMismatch,
};

/// Hash a password using PBKDF2-HMAC-SHA256 with a random salt.
/// Returns an owned string in the format: "$pbkdf2-sha256${iterations}${salt_hex}${hash_hex}"
pub fn hash(gpa: std.mem.Allocator, plaintext: []const u8) ![]const u8 {
    // Generate random salt
    var salt: [SALT_LEN]u8 = undefined;
    var seed: [32]u8 = undefined;
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch return error.OutOfMemory;
    @memcpy(seed[0..8], std.mem.asBytes(&ts.sec));
    @memcpy(seed[8..16], std.mem.asBytes(&ts.nsec));
    var i: usize = 16;
    while (i < 32) : (i += 8) {
        @memcpy(seed[i..@min(i + 8, 32)], seed[0..@min(8, 32 - i)]);
    }
    var csprng = Random.DefaultCsprng.init(seed);
    csprng.random().bytes(&salt);

    // Derive key
    var dk: [HASH_LEN]u8 = undefined;
    try pbkdf2(&dk, plaintext, &salt, ITERATIONS, HmacSha256);

    // Encode as: $pbkdf2-sha256$<iterations>$<salt_hex>$<hash_hex>
    const salt_hex = std.fmt.bytesToHex(salt, .lower);
    const hash_hex = std.fmt.bytesToHex(dk, .lower);
    const result = try std.fmt.allocPrint(gpa, "$pbkdf2-sha256${d}$", .{ITERATIONS});
    const part2 = try std.fmt.allocPrint(gpa, "{s}${s}", .{ &salt_hex, &hash_hex });
    const full = try std.mem.concat(gpa, u8, &.{ result, part2 });
    gpa.free(result);
    gpa.free(part2);
    log.debug("hashed password (len={d})", .{plaintext.len});
    return full;
}

/// Verify a password against a stored hash.
pub fn verify(stored_hash: []const u8, plaintext: []const u8) !bool {
    // Parse: $pbkdf2-sha256$<iterations>$<salt_hex>$<hash_hex>
    if (!std.mem.startsWith(u8, stored_hash, "$pbkdf2-sha256$")) return error.InvalidHashFormat;

    const rest = stored_hash["$pbkdf2-sha256$".len..];

    // Find iterations
    const dollar1 = std.mem.indexOfScalar(u8, rest, '$') orelse return error.InvalidHashFormat;
    const iter_str = rest[0..dollar1];
    const iterations = std.fmt.parseInt(u32, iter_str, 10) catch return error.InvalidHashFormat;

    const after_iter = rest[dollar1 + 1 ..];

    // Find salt
    const dollar2 = std.mem.indexOfScalar(u8, after_iter, '$') orelse return error.InvalidHashFormat;
    const salt_hex_str = after_iter[0..dollar2];
    if (salt_hex_str.len != SALT_LEN * 2) return error.InvalidHashFormat;

    var salt: [SALT_LEN]u8 = undefined;
    hexDecode(&salt, salt_hex_str) catch return error.InvalidHashFormat;

    const hash_hex_str = after_iter[dollar2 + 1 ..];
    if (hash_hex_str.len != HASH_LEN * 2) return error.InvalidHashFormat;

    // Derive key with same parameters
    var dk: [HASH_LEN]u8 = undefined;
    try pbkdf2(&dk, plaintext, &salt, iterations, HmacSha256);

    // Constant-time compare
    const expected_hex = std.fmt.bytesToHex(dk, .lower);
    return std.crypto.timing_safe.eql([HASH_LEN * 2]u8, expected_hex, hash_hex_str[0 .. HASH_LEN * 2].*);
}

/// Decode hex string into bytes.
fn hexDecode(out: []u8, hex: []const u8) !void {
    if (hex.len != out.len * 2) return error.InvalidHashFormat;
    for (0..out.len) |i| {
        out[i] = try std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16);
    }
}

test {
    std.testing.refAllDecls(@This());
}
