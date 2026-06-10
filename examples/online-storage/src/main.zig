const std = @import("std");
const zypher = @import("zypher");
const server = @import("infrastructure/server.zig");
const handlers = @import("presentation/handlers.zig");

pub fn main(init: std.process.Init) !void {
    try server.serve(init);
}

test "clean architecture service returns a title" {
    const service = @import("application/home_service.zig");
    try std.testing.expect(service.homeGreeting().title.len > 0);
}

test "online storage rejects unsafe filenames" {
    const service = @import("application/home_service.zig");
    try std.testing.expect(service.isSafeFilename("report.txt"));
    try std.testing.expect(!service.isSafeFilename("../secret.txt"));
    try std.testing.expect(!service.isSafeFilename("nested/file.txt"));
}

test "online storage uploads and downloads file bytes" {
    const gpa = std.testing.allocator;

    var upload_req = zypher.core.Request{
        .method = .post,
        .path = "/upload",
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
        .files = std.StringHashMap(zypher.core.Request.FileUpload).init(gpa),
        .files_owned = true,
    };
    defer upload_req.deinit();
    try upload_req.files.put(try gpa.dupe(u8, "file"), .{
        .filename = try gpa.dupe(u8, "unit-upload.txt"),
        .content_type = try gpa.dupe(u8, "text/plain"),
        .data = try gpa.dupe(u8, "stored bytes"),
    });

    var upload_res = zypher.core.Response.init(gpa);
    defer upload_res.deinit();
    handlers.upload(&upload_req, &upload_res);
    try std.testing.expectEqual(@as(u16, 200), upload_res.status_code);

    var params = zypher.router.RouteParams.init(gpa);
    defer params.deinit();
    try params.put("name", "unit-upload.txt");
    var download_req = zypher.core.Request{
        .method = .get,
        .path = "/files/unit-upload.txt",
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
        .params = params,
    };
    defer download_req.deinit();

    var download_res = zypher.core.Response.init(gpa);
    defer download_res.deinit();
    handlers.download(&download_req, &download_res);
    try std.testing.expectEqual(@as(u16, 200), download_res.status_code);
    try std.testing.expectEqualStrings("stored bytes", download_res.body.?);
    try std.testing.expectEqualStrings("application/octet-stream", download_res.headers.get("Content-Type").?);
}
