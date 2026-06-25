const std = @import("std");

pub fn randomBytes(io: std.Io, buf: []u8) void {
    io.random(buf);
}
