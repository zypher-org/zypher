const std = @import("std");
const zypher = @import("zypher");

const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Server = zypher.core.Server;

const storage_dir = "storage";
var io: std.Io = undefined;

pub fn main(init: std.process.Init) !void {
    io = init.io;
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, storage_dir, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };

    var server = Server.init(.{
        .host = "127.0.0.1",
        .port = 8080,
        .max_body_size = 100 * 1024 * 1024 * 1024, // 100 GB limit
        .max_inline_body_size = 1_048_576, // 1 MiB — larger bodies stream via req.body_stream
    });

    try server.listenAndServe(io, init.gpa, handler);
}

fn handler(req: *Request, res: *Response) void {
    if (std.mem.eql(u8, req.path, "/")) return index(req, res);
    if (std.mem.eql(u8, req.path, "/upload")) return upload(req, res);
    if (std.mem.startsWith(u8, req.path, "/files/")) return download(req, res);
    _ = res.status(404);
    res.text("Not Found") catch {};
}

fn index(_: *Request, res: *Response) void {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(res.allocator);
    const gpa = res.allocator;
    buf.appendSlice(gpa,
        \\<!DOCTYPE html>
        \\<html><head><title>Large File Upload</title>
        \\<meta charset="utf-8"></head><body>
        \\<h1>Large File Upload Demo</h1>
        \\<p>Files &gt; 1 MiB are streamed to disk without buffering in RAM.</p>
        \\<form method="post" action="/upload" enctype="application/octet-stream">
        \\  <label>File: <input type="file" name="file" required></label>
        \\  <button type="submit">Upload</button>
        \\</form>
        \\<h2>Stored Files</h2><ul>
    ) catch return;

    var dir = std.Io.Dir.cwd().openDir(io, storage_dir, .{ .iterate = true }) catch {
        res.html(buf.items) catch {};
        return;
    };
    defer dir.close(io);

    var it = std.Io.Dir.iterate(dir);
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        const link = std.fmt.allocPrint(gpa, "<li><a href=\"/files/{s}\">{s}</a></li>", .{ entry.name, entry.name }) catch return;
        defer gpa.free(link);
        buf.appendSlice(gpa, link) catch return;
    }

    buf.appendSlice(gpa, "</ul></body></html>") catch return;
    res.html(buf.items) catch {};
}

fn upload(req: *Request, res: *Response) void {
    // Generate a unique filename from the current timestamp
    const ts = unixTimestamp();
    const filename = std.fmt.allocPrint(res.allocator, "{d}", .{ts}) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(filename);

    const path = std.fs.path.join(res.allocator, &.{ storage_dir, filename }) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(path);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
        .CLOEXEC = true,
    }, 0o644) catch |err| {
        _ = res.status(500);
        res.text(std.fmt.allocPrint(res.allocator, "open error: {}", .{err}) catch "open error") catch {};
        return;
    };
    defer _ = std.posix.system.close(fd);

    // ── Decide whether the body is inline (buffered) or streamed ─────
    if (req.body_stream) |*body_stream| {
        // Large file: stream from network directly to disk
        var chunk: [65536]u8 = undefined;
        var total: usize = 0;
        while (true) {
            const n = body_stream.read(chunk[0..]) catch |err| {
                _ = res.status(500);
                res.text(std.fmt.allocPrint(res.allocator, "read error: {}", .{err}) catch "read error") catch {};
                return;
            };
            if (n == 0) break;
            var written: usize = 0;
            while (written < n) {
                const m = writeAll(fd, chunk[written..n]) catch |err| {
                    _ = res.status(500);
                    res.text(std.fmt.allocPrint(res.allocator, "write error: {}", .{err}) catch "write error") catch {};
                    return;
                };
                written += m;
            }
            total += n;
        }
        const body = std.fmt.allocPrint(res.allocator,
            \\<p>Uploaded <strong>{s}</strong> ({d} bytes, <em>streamed</em>)</p>
            \\<p><a href="/files/{s}">Download</a></p>
            \\<p><a href="/">Back</a></p>
        , .{ filename, total, filename }) catch {
            _ = res.status(500);
            return;
        };
        defer res.allocator.free(body);
        res.html(body) catch {};
    } else {
        // Small file: already buffered in req.body
        var written: usize = 0;
        while (written < req.body.len) {
            const n = writeAll(fd, req.body[written..]) catch |err| {
                _ = res.status(500);
                res.text(std.fmt.allocPrint(res.allocator, "write error: {}", .{err}) catch "write error") catch {};
                return;
            };
            written += n;
        }
        const body = std.fmt.allocPrint(res.allocator,
            \\<p>Uploaded <strong>{s}</strong> ({d} bytes, <em>inline</em>)</p>
            \\<p><a href="/files/{s}">Download</a></p>
            \\<p><a href="/">Back</a></p>
        , .{ filename, req.body.len, filename }) catch {
            _ = res.status(500);
            return;
        };
        defer res.allocator.free(body);
        res.html(body) catch {};
    }
}

fn download(req: *Request, res: *Response) void {
    const name = req.path["/files/".len..];
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null or
        std.mem.indexOf(u8, name, "..") != null)
    {
        _ = res.status(400);
        res.text("Invalid filename") catch {};
        return;
    }
    const path = std.fs.path.join(res.allocator, &.{ storage_dir, name }) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(path);

    // Read file into memory for download.
    // For production large-file serving, use the static middleware instead.
    const data = readFileAlloc(res.allocator, path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                _ = res.status(404);
                res.text("File Not Found") catch {};
            },
            error.FileTooLarge => {
                _ = res.status(413);
                res.text("File too large to buffer in memory") catch {};
            },
            else => {
                _ = res.status(500);
                res.text("Internal Server Error") catch {};
            },
        }
        return;
    };
    if (data.len == 0) return; // readFileAlloc sent the error response

    const disposition = std.fmt.allocPrint(res.allocator, "attachment; filename=\"{s}\"", .{name}) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(disposition);
    _ = res.header("Content-Type", "application/octet-stream");
    _ = res.header("Content-Disposition", disposition);
    if (res.body) |old| res.allocator.free(old);
    res.body = data;
}

/// Read a file into an allocated buffer (max 10 MiB for this example).
fn readFileAlloc(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer _ = std.posix.system.close(fd);

    const size = @as(u64, @intCast(lseek(fd, 0, 2))); // SEEK_END
    _ = lseek(fd, 0, 0); // SEEK_SET — rewind

    const max_download: u64 = 10 * 1024 * 1024; // 10 MiB
    if (size > max_download) return error.FileTooLarge;

    const buf = try gpa.alloc(u8, @intCast(size));
    errdefer gpa.free(buf);

    var total: usize = 0;
    while (total < size) {
        const n = try std.posix.read(fd, buf[total..]);
        if (n == 0) break;
        total += n;
    }
    return buf;
}

/// Platform-specific write(2) — returns bytes written (may be &lt; buf.len).
fn writeAll(fd: std.posix.fd_t, buf: []const u8) !usize {
    if (comptime @import("builtin").os.tag == .linux) {
        const rc = std.os.linux.write(fd, buf.ptr, buf.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => return 0,
            else => return error.WriteFailed,
        }
    }
    const rc = std.posix.system.write(fd, buf.ptr, buf.len);
    if (rc < 0) return error.WriteFailed;
    return @intCast(rc);
}

/// Returns the current Unix timestamp in seconds.
fn unixTimestamp() i64 {
    return std.Io.Timestamp.now(io, .real).toSeconds();
}

/// Platform-specific lseek(2).
fn lseek(fd: std.posix.fd_t, offset: i64, whence: u32) i64 {
    if (comptime @import("builtin").os.tag == .linux) {
        return @as(i64, @bitCast(std.os.linux.lseek(fd, offset, whence)));
    }
    return std.posix.system.lseek(fd, offset, whence);
}
