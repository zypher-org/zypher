const std = @import("std");
const zypher = @import("zypher");
const service = @import("../application/home_service.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;

pub fn index(_: *Request, res: *Response) void {
    const greeting = service.homeGreeting();
    const body = std.fmt.allocPrint(
        res.allocator,
        \\<h1>{s}</h1>
        \\<p>{s}</p>
        \\<form method="post" action="/upload" enctype="multipart/form-data">
        \\  <label>File <input type="file" name="file" required></label>
        \\  <button type="submit">Upload</button>
        \\</form>
    ,
        .{ greeting.title, greeting.message },
    ) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(body);
    res.html(body) catch {};
}

pub fn upload(req: *Request, res: *Response) void {
    const upload_file = req.file("file") orelse {
        _ = res.status(400);
        res.text("missing multipart file field 'file'") catch {};
        return;
    };
    const stored = service.saveUpload(upload_file) catch |err| {
        _ = res.status(400);
        const body = std.fmt.allocPrint(res.allocator, "upload failed: {s}", .{@errorName(err)}) catch {
            res.text("upload failed") catch {};
            return;
        };
        defer res.allocator.free(body);
        res.text(body) catch {};
        return;
    };
    const body = std.fmt.allocPrint(
        res.allocator,
        "<p>Uploaded {s} ({d} bytes)</p><p><a href=\"/files/{s}\">Download</a></p>",
        .{ stored.name, stored.size, stored.name },
    ) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(body);
    res.html(body) catch {};
}

pub fn download(req: *Request, res: *Response) void {
    const name = req.params.get("name") orelse {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    const bytes = service.readFile(res.allocator, name) catch |err| {
        _ = res.status(if (err == error.FileNotFound) 404 else 400);
        res.text("file not found") catch {};
        return;
    };
    if (res.body) |old| res.allocator.free(old);
    res.body = bytes;
    _ = res.header("Content-Type", "application/octet-stream");
    const disposition = std.fmt.allocPrint(res.allocator, "attachment; filename=\"{s}\"", .{name}) catch return;
    defer res.allocator.free(disposition);
    _ = res.header("Content-Disposition", disposition);
}
