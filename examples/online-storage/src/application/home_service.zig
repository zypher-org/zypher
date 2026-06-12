const std = @import("std");
const domain = @import("../domain/greeting.zig");

pub const storage_dir = "storage";

pub fn homeGreeting() domain.Greeting {
    return .{
        .title = "Online Storage",
        .message = "Upload a file, then download it by filename.",
    };
}

pub fn isSafeFilename(name: []const u8) bool {
    if (name.len == 0 or name.len > 128) return false;
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    for (name) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '_' or ch == '-')) return false;
    }
    return true;
}

pub fn saveUpload(upload: anytype) !domain.StoredFile {
    if (!isSafeFilename(upload.filename)) return error.InvalidFilename;
    try ensureStorageDir();
    const dir_fd = try std.posix.openat(std.posix.AT.FDCWD, storage_dir, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    defer closeFd(dir_fd);
    const fd = try std.posix.openat(
        dir_fd,
        upload.filename,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true },
        0o644,
    );
    defer closeFd(fd);

    var written: usize = 0;
    while (written < upload.data.len) {
        const chunk = upload.data[written..];
        const rc = std.os.linux.write(fd, chunk.ptr, chunk.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                const n: usize = @intCast(rc);
                if (n == 0) return error.WriteFailed;
                written += n;
            },
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
    return .{ .name = upload.filename, .size = upload.data.len };
}

pub fn readFile(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    if (!isSafeFilename(name)) return error.InvalidFilename;
    try ensureStorageDir();
    const dir_fd = try std.posix.openat(std.posix.AT.FDCWD, storage_dir, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    defer closeFd(dir_fd);
    const fd = try std.posix.openat(dir_fd, name, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer closeFd(fd);

    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(gpa);
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &buf);
        if (n == 0) break;
        try bytes.appendSlice(gpa, buf[0..n]);
        if (bytes.items.len > 10 * 1024 * 1024) return error.FileTooLarge;
    }
    return try bytes.toOwnedSlice(gpa);
}

fn ensureStorageDir() !void {
    const path = storage_dir ++ "\x00";
    const rc = std.os.linux.mkdir(path.ptr, 0o755);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .EXIST => {},
        else => return error.StorageUnavailable,
    }
}

fn closeFd(fd: std.posix.fd_t) void {
    _ = std.posix.system.close(fd);
}
