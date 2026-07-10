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

fn ensureStorageDir(io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, storage_dir, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
}

pub fn saveUpload(io: std.Io, upload: anytype) !domain.StoredFile {
    if (!isSafeFilename(upload.filename)) return error.InvalidFilename;
    try ensureStorageDir(io);
    const cwd = std.Io.Dir.cwd();
    const dir = try cwd.openDir(io, storage_dir, .{});
    defer dir.close(io);
    const file = try dir.createFile(io, upload.filename, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, upload.data);
    return .{ .name = upload.filename, .size = upload.data.len };
}

pub fn readFile(io: std.Io, gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    if (!isSafeFilename(name)) return error.InvalidFilename;
    try ensureStorageDir(io);
    const cwd = std.Io.Dir.cwd();
    const dir = try cwd.openDir(io, storage_dir, .{});
    defer dir.close(io);
    const file = try dir.openFile(io, name, .{ .mode = .read_only });
    defer file.close(io);

    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(gpa);
    var buf: [8192]u8 = undefined;
    while (true) {
        var data: [1][]u8 = .{&buf};
        const n = std.Io.File.readStreaming(file, io, &data) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        if (n == 0) break;
        try bytes.appendSlice(gpa, buf[0..n]);
        if (bytes.items.len > 10 * 1024 * 1024) return error.FileTooLarge;
    }
    return try bytes.toOwnedSlice(gpa);
}
