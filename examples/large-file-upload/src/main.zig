const std = @import("std");
const zypher = @import("zypher");

const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Server = zypher.core.Server;
const urlEncode = zypher.core.urlEncode;
const urlDecode = zypher.core.urlDecode;

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
        .max_body_size = 100 * 1024 * 1024 * 1024,
        .max_inline_body_size = 1_048_576,
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
        \\<form method="post" action="/upload" enctype="multipart/form-data">
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
        const link_name = urlEncode(gpa, entry.name) catch return;
        const link = std.fmt.allocPrint(gpa, "<li><a href=\"/files/{s}\">{s}</a></li>", .{ link_name, entry.name }) catch return;
        defer gpa.free(link);
        defer gpa.free(link_name);
        buf.appendSlice(gpa, link) catch return;
    }

    buf.appendSlice(gpa, "</ul></body></html>") catch return;
    res.html(buf.items) catch {};
}

fn upload(req: *Request, res: *Response) void {
    const content_type = req.header("Content-Type") orelse {
        _ = res.status(400);
        res.text("Missing Content-Type header") catch {};
        return;
    };

    if (req.body_stream) |*body_stream| {
        uploadStreamed(req, body_stream, content_type, res);
    } else {
        uploadInline(req, content_type, res);
    }
}

fn uploadInline(req: *Request, content_type: []const u8, res: *Response) void {
    const form_ = Request.parseMultipartFormData(res.allocator, content_type, req.body) catch |err| {
        _ = res.status(400);
        const msg = std.fmt.allocPrint(res.allocator, "Failed to parse multipart form: {}", .{err}) catch "parse error";
        defer res.allocator.free(msg);
        res.text(msg) catch {};
        return;
    };
    var form: Request.MultipartForm = form_;
    const form_ptr: *Request.MultipartForm = &form;

    const file = form_ptr.files.get("file") orelse {
        form_ptr.deinit();
        _ = res.status(400);
        res.text("No file field found") catch {};
        return;
    };

    const safe_name = sanitizeFilename(res.allocator, file.filename) orelse {
        form_ptr.deinit();
        _ = res.status(400);
        res.text("Invalid filename") catch {};
        return;
    };

    const path = std.fs.path.join(res.allocator, &.{ storage_dir, safe_name }) catch {
        form_ptr.deinit();
        res.allocator.free(safe_name);
        _ = res.status(500);
        return;
    };

    const cwd = std.Io.Dir.cwd();
    const file_out = cwd.createFile(io, path, .{}) catch |err| {
        form_ptr.deinit();
        res.allocator.free(safe_name);
        res.allocator.free(path);
        _ = res.status(500);
        res.text(std.fmt.allocPrint(res.allocator, "open error: {}", .{err}) catch "open error") catch {};
        return;
    };
    defer file_out.close(io);

    file_out.writeStreamingAll(io, file.data) catch |err| {
        form_ptr.deinit();
        res.allocator.free(safe_name);
        res.allocator.free(path);
        _ = res.status(500);
        res.text(std.fmt.allocPrint(res.allocator, "write error: {}", .{err}) catch "write error") catch {};
        return;
    };

    const url_name = urlEncode(res.allocator, safe_name) catch {
        form_ptr.deinit();
        res.allocator.free(safe_name);
        res.allocator.free(path);
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(url_name);
    const body = std.fmt.allocPrint(res.allocator,
        \\<p>Uploaded <strong>{s}</strong> ({d} bytes, <em>inline</em>)</p>
        \\<p><a href="/files/{s}">Download</a></p>
        \\<p><a href="/">Back</a></p>
    , .{ safe_name, file.data.len, url_name }) catch {
        form_ptr.deinit();
        res.allocator.free(safe_name);
        res.allocator.free(path);
        _ = res.status(500);
        return;
    };

    res.html(body) catch {};
    form_ptr.deinit();
    res.allocator.free(safe_name);
    res.allocator.free(path);
    res.allocator.free(body);
}

fn uploadStreamed(_: *Request, body_stream: *Request.BodyStream, content_type: []const u8, res: *Response) void {
    const gpa = res.allocator;

    const boundary = extractBoundary(gpa, content_type) orelse {
        _ = res.status(400);
        res.text("Missing multipart boundary") catch {};
        return;
    };
    defer gpa.free(boundary);

    const marker = std.fmt.allocPrint(gpa, "\r\n--{s}", .{boundary}) catch {
        _ = res.status(500);
        return;
    };
    defer gpa.free(marker);

    var hbuf: [4096]u8 = undefined;
    var hlen: usize = 0;

    while (hlen < hbuf.len) {
        const n = body_stream.read(hbuf[hlen..]) catch |err| {
            _ = res.status(500);
            res.text(std.fmt.allocPrint(gpa, "read error: {}", .{err}) catch "read error") catch {};
            return;
        };
        if (n == 0) {
            _ = res.status(400);
            res.text("Unexpected end of multipart stream") catch {};
            return;
        }
        hlen += n;

        if (std.mem.indexOf(u8, hbuf[0..hlen], "\r\n\r\n")) |pos| {
            const headers = hbuf[0..pos];
            const body_start = pos + 4;

            const raw_name = extractFilenameFromHeaders(headers) orelse {
                _ = res.status(400);
                res.text("Missing filename in multipart headers") catch {};
                return;
            };
            const safe_name = sanitizeFilename(gpa, raw_name) orelse {
                _ = res.status(400);
                res.text("Invalid filename") catch {};
                return;
            };

            const path = std.fs.path.join(gpa, &.{ storage_dir, safe_name }) catch {
                _ = res.status(500);
                gpa.free(safe_name);
                return;
            };

            const cwd = std.Io.Dir.cwd();
            const file_out = cwd.createFile(io, path, .{}) catch |err| {
                _ = res.status(500);
                res.text(std.fmt.allocPrint(gpa, "open error: {}", .{err}) catch "open error") catch {};
                gpa.free(safe_name);
                gpa.free(path);
                return;
            };
            defer file_out.close(io);

            const remaining = hbuf[body_start..hlen];
            var total: usize = 0;
            var buf: [65536]u8 = undefined;

            const win_size = marker.len;
            var window = std.ArrayList(u8).empty;
            defer window.deinit(gpa);

            window.appendSlice(gpa, remaining) catch {
                _ = res.status(500);
                gpa.free(safe_name);
                gpa.free(path);
                return;
            };

            while (true) {
                const nr = body_stream.read(&buf) catch |err| {
                    _ = res.status(500);
                    res.text(std.fmt.allocPrint(gpa, "read error: {}", .{err}) catch "read error") catch {};
                    gpa.free(safe_name);
                    gpa.free(path);
                    return;
                };
                if (nr > 0) {
                    window.appendSlice(gpa, buf[0..nr]) catch {
                        _ = res.status(500);
                        gpa.free(safe_name);
                        gpa.free(path);
                        return;
                    };
                }

                if (std.mem.indexOf(u8, window.items, marker)) |mp| {
                    file_out.writeStreamingAll(io, window.items[0..mp]) catch {};
                    break;
                }

                if (nr == 0) {
                    file_out.writeStreamingAll(io, window.items) catch {};
                    break;
                }

                if (window.items.len > win_size) {
                    const flush_end = window.items.len - win_size;
                    file_out.writeStreamingAll(io, window.items[0..flush_end]) catch |err| {
                        _ = res.status(500);
                        res.text(std.fmt.allocPrint(gpa, "write error: {}", .{err}) catch "write error") catch {};
                        gpa.free(safe_name);
                        gpa.free(path);
                        return;
                    };
                    total += flush_end;
                    const trail = window.items[flush_end..];
                    window = std.ArrayList(u8).empty;
                    window.appendSlice(gpa, trail) catch {
                        _ = res.status(500);
                        gpa.free(safe_name);
                        gpa.free(path);
                        return;
                    };
                }
            }

            const url_name = urlEncode(gpa, safe_name) catch {
                gpa.free(safe_name);
                gpa.free(path);
                _ = res.status(500);
                return;
            };
            defer gpa.free(url_name);
            const body = std.fmt.allocPrint(gpa,
                \\<p>Uploaded <strong>{s}</strong> ({d} bytes, <em>streamed</em>)</p>
                \\<p><a href="/files/{s}">Download</a></p>
                \\<p><a href="/">Back</a></p>
            , .{ safe_name, total, url_name }) catch {
                gpa.free(safe_name);
                gpa.free(path);
                _ = res.status(500);
                return;
            };
            defer gpa.free(body);
            gpa.free(safe_name);
            gpa.free(path);
            res.html(body) catch {};
            return;
        }
    }

    _ = res.status(400);
    res.text("Multipart headers too large or malformed") catch {};
}

fn download(req: *Request, res: *Response) void {
    const raw_name = req.path["/files/".len..];
    if (raw_name.len == 0 or std.mem.indexOfScalar(u8, raw_name, '/') != null or
        std.mem.indexOf(u8, raw_name, "..") != null)
    {
        _ = res.status(400);
        res.text("Invalid filename") catch {};
        return;
    }
    const name = urlDecode(res.allocator, raw_name) catch {
        _ = res.status(400);
        res.text("Invalid URL encoding") catch {};
        return;
    };
    defer res.allocator.free(name);

    if (name.len == 0 or name.len > 255 or
        std.mem.indexOfScalar(u8, name, '/') != null or
        std.mem.indexOf(u8, name, "..") != null or
        std.mem.indexOfScalar(u8, name, '\x00') != null)
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

    const file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                _ = res.status(404);
                res.text("File Not Found") catch {};
            },
            else => {
                _ = res.status(500);
                res.text("Internal Server Error") catch {};
            },
        }
        return;
    };

    const size = io.vtable.fileLength(io.userdata, file) catch @as(u64, 0);

    const disposition = std.fmt.allocPrint(res.allocator, "attachment; filename=\"{s}\"", .{name}) catch {
        file.close(io);
        _ = res.status(500);
        return;
    };
    _ = res.header("Content-Type", "application/octet-stream");
    _ = res.header("Content-Disposition", disposition);
    res.setFileBody(file.handle, @intCast(size)) catch {
        file.close(io);
        _ = res.status(500);
        return;
    };
}

fn extractBoundary(gpa: std.mem.Allocator, content_type: []const u8) ?[]u8 {
    var it = std.mem.splitScalar(u8, content_type, ';');
    _ = it.next() orelse return null;
    while (it.next()) |param| {
        const trimmed = std.mem.trim(u8, param, " \t");
        if (std.mem.startsWith(u8, trimmed, "boundary=")) {
            var value = trimmed["boundary=".len..];
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }
            return gpa.dupe(u8, value) catch null;
        }
    }
    return null;
}

fn extractFilenameFromHeaders(headers: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (lines.next()) |line| {
        if (std.mem.indexOfScalar(u8, line, ':')) |idx| {
            const header_name = std.mem.trim(u8, line[0..idx], " \t");
            const header_value = std.mem.trim(u8, line[idx + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(header_name, "Content-Disposition")) {
                return dispositionParam(header_value, "filename");
            }
        }
    }
    return null;
}

fn dispositionParam(value: []const u8, param_name: []const u8) ?[]const u8 {
    var parts = std.mem.splitScalar(u8, value, ';');
    _ = parts.next();
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        if (!std.mem.eql(u8, key, param_name)) continue;
        var param_value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        if (param_value.len >= 2 and param_value[0] == '"' and param_value[param_value.len - 1] == '"') {
            param_value = param_value[1 .. param_value.len - 1];
        }
        return param_value;
    }
    return null;
}

fn sanitizeFilename(gpa: std.mem.Allocator, name: []const u8) ?[]u8 {
    if (name.len == 0 or name.len > 255) return null;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return null;
    if (std.mem.indexOf(u8, name, "..") != null) return null;
    if (std.mem.indexOfScalar(u8, name, '\x00') != null) return null;
    return gpa.dupe(u8, name) catch null;
}
