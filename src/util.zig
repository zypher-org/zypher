const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub fn randomBytes(buf: []u8) !void {
    if (buf.len == 0) return;

    if (builtin.os.tag == .linux) {
        var filled: usize = 0;
        while (filled < buf.len) {
            const remaining = buf[filled..];
            const rc = std.os.linux.getrandom(remaining.ptr, remaining.len, 0);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    const n: usize = @intCast(rc);
                    if (n == 0) return error.EntropyUnavailable;
                    filled += n;
                },
                .INTR => continue,
                else => return error.EntropyUnavailable,
            }
        }
        return;
    }

    if (builtin.link_libc and @TypeOf(posix.system.arc4random_buf) != void) {
        posix.system.arc4random_buf(buf.ptr, buf.len);
        return;
    }

    return error.EntropyUnavailable;
}
