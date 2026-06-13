/// Unit tests for zypher Static file middleware.
const std = @import("std");
const Chain = @import("zypher").middleware.Chain;
const static_mw = @import("zypher").middleware.static;
const Request = @import("zypher").core.Request;
const Response = @import("zypher").core.Response;

fn makeRequest(gpa: std.mem.Allocator, method: @import("zypher").core.Method, path: []const u8) Request {
    return .{
        .method = method,
        .path = path,
        .query = std.StringHashMap([]const u8).init(gpa),
        .headers = std.StringHashMap([]const u8).init(gpa),
        .body = &.{},
        .allocator = gpa,
    };
}

fn ok_handler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(200);
    res.text("ok") catch {};
}

test "Static: path traversal is rejected with 403" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = "/tmp/zypher-test-static" })});

    var req = makeRequest(gpa, .get, "/../../etc/passwd");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 403), res.status_code);
}

test "Static: non-prefix path passes through to handler" {
    const gpa = std.testing.allocator;

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = "/tmp/zypher-test-static", .prefix = "/static" })});

    var req = makeRequest(gpa, .get, "/api/data");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    // /api/data doesn't start with /static prefix, so passes through
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}

test "Static: serves file from configured directory" {
    const gpa = std.testing.allocator;
    const root_dir = ".zig-cache/tmp/zypher-static-serve";
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(std.testing.io, root_dir) catch {};
    try cwd.writeFile(std.testing.io, .{ .sub_path = root_dir ++ "/style.css", .data = "body{color:red}" });

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = root_dir, .prefix = "/static" })});

    var req = makeRequest(gpa, .get, "/static/style.css");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expectEqualStrings("body{color:red}", res.body.?);
    try std.testing.expectEqualStrings("text/css", res.headers.get("Content-Type").?);
    try std.testing.expect(res.headers.get("Last-Modified") != null);
}

test "Static: If-Modified-Since returns 304 for matching Last-Modified" {
    const gpa = std.testing.allocator;
    const root_dir = ".zig-cache/tmp/zypher-static-last-modified";
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(std.testing.io, root_dir) catch {};
    try cwd.writeFile(std.testing.io, .{ .sub_path = root_dir ++ "/app.js", .data = "console.log('ok')" });

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = root_dir, .prefix = "/static" })});

    var first_req = makeRequest(gpa, .get, "/static/app.js");
    defer first_req.deinit();
    var first_res = Response.init(gpa);
    defer first_res.deinit();
    MyChain.run(&first_req, &first_res, ok_handler);
    const last_modified = first_res.headers.get("Last-Modified").?;

    var cached_req = makeRequest(gpa, .get, "/static/app.js");
    defer cached_req.deinit();
    try cached_req.headers.put("If-Modified-Since", last_modified);
    var cached_res = Response.init(gpa);
    defer cached_res.deinit();

    MyChain.run(&cached_req, &cached_res, ok_handler);

    try std.testing.expectEqual(@as(u16, 304), cached_res.status_code);
    try std.testing.expect(cached_res.body == null);
    try std.testing.expectEqualStrings(last_modified, cached_res.headers.get("Last-Modified").?);
}

test "Static: missing file passes through to handler" {
    const gpa = std.testing.allocator;
    const root_dir = ".zig-cache/tmp/zypher-static-empty";
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(std.testing.io, root_dir) catch {};

    const MyChain = comptime Chain(.{static_mw.middlewareWith(.{ .root_dir = root_dir, .prefix = "/static" })});

    var req = makeRequest(gpa, .get, "/static/missing.txt");
    defer req.deinit();
    var res = Response.init(gpa);
    defer res.deinit();

    MyChain.run(&req, &res, ok_handler);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expectEqualStrings("ok", res.body.?);
}

test "Static: MIME type detection by extension" {
    // Existing
    try std.testing.expectEqualStrings("text/css", static_mw.detectMime("style.css"));
    try std.testing.expectEqualStrings("application/javascript", static_mw.detectMime("app.js"));
    try std.testing.expectEqualStrings("text/html; charset=utf-8", static_mw.detectMime("index.html"));
    try std.testing.expectEqualStrings("application/octet-stream", static_mw.detectMime("data.bin"));

    // Web / text
    try std.testing.expectEqualStrings("application/javascript", static_mw.detectMime("app.mjs"));
    try std.testing.expectEqualStrings("application/javascript", static_mw.detectMime("app.cjs"));
    try std.testing.expectEqualStrings("application/javascript", static_mw.detectMime("app.jsx"));
    try std.testing.expectEqualStrings("application/json", static_mw.detectMime("index.map"));
    try std.testing.expectEqualStrings("application/yaml", static_mw.detectMime("config.yaml"));
    try std.testing.expectEqualStrings("application/yaml", static_mw.detectMime("config.yml"));
    try std.testing.expectEqualStrings("application/toml", static_mw.detectMime("config.toml"));
    try std.testing.expectEqualStrings("application/typescript", static_mw.detectMime("app.ts"));
    try std.testing.expectEqualStrings("application/typescript", static_mw.detectMime("component.tsx"));

    // Images
    try std.testing.expectEqualStrings("image/bmp", static_mw.detectMime("image.bmp"));
    try std.testing.expectEqualStrings("image/avif", static_mw.detectMime("image.avif"));

    // Fonts
    try std.testing.expectEqualStrings("font/otf", static_mw.detectMime("font.otf"));
    try std.testing.expectEqualStrings("application/vnd.ms-fontobject", static_mw.detectMime("font.eot"));

    // Video
    try std.testing.expectEqualStrings("video/mp4", static_mw.detectMime("video.mp4"));
    try std.testing.expectEqualStrings("video/webm", static_mw.detectMime("video.webm"));
    try std.testing.expectEqualStrings("video/x-matroska", static_mw.detectMime("video.mkv"));
    try std.testing.expectEqualStrings("video/x-msvideo", static_mw.detectMime("video.avi"));
    try std.testing.expectEqualStrings("video/quicktime", static_mw.detectMime("video.mov"));
    try std.testing.expectEqualStrings("video/x-ms-wmv", static_mw.detectMime("video.wmv"));
    try std.testing.expectEqualStrings("video/x-flv", static_mw.detectMime("video.flv"));
    try std.testing.expectEqualStrings("video/x-m4v", static_mw.detectMime("video.m4v"));
    try std.testing.expectEqualStrings("video/3gpp", static_mw.detectMime("video.3gp"));
    try std.testing.expectEqualStrings("video/ogg", static_mw.detectMime("video.ogv"));

    // Audio
    try std.testing.expectEqualStrings("audio/mpeg", static_mw.detectMime("audio.mp3"));
    try std.testing.expectEqualStrings("audio/wav", static_mw.detectMime("audio.wav"));
    try std.testing.expectEqualStrings("audio/ogg", static_mw.detectMime("audio.ogg"));
    try std.testing.expectEqualStrings("audio/flac", static_mw.detectMime("audio.flac"));
    try std.testing.expectEqualStrings("audio/aac", static_mw.detectMime("audio.aac"));
    try std.testing.expectEqualStrings("audio/x-ms-wma", static_mw.detectMime("audio.wma"));
    try std.testing.expectEqualStrings("audio/mp4", static_mw.detectMime("audio.m4a"));
    try std.testing.expectEqualStrings("audio/opus", static_mw.detectMime("audio.opus"));

    // Documents
    try std.testing.expectEqualStrings("application/pdf", static_mw.detectMime("doc.pdf"));
    try std.testing.expectEqualStrings("application/msword", static_mw.detectMime("doc.doc"));
    try std.testing.expectEqualStrings("application/vnd.openxmlformats-officedocument.wordprocessingml.document", static_mw.detectMime("doc.docx"));
    try std.testing.expectEqualStrings("application/vnd.ms-excel", static_mw.detectMime("spreadsheet.xls"));
    try std.testing.expectEqualStrings("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", static_mw.detectMime("spreadsheet.xlsx"));
    try std.testing.expectEqualStrings("application/vnd.ms-powerpoint", static_mw.detectMime("slides.ppt"));
    try std.testing.expectEqualStrings("application/vnd.openxmlformats-officedocument.presentationml.presentation", static_mw.detectMime("slides.pptx"));
    try std.testing.expectEqualStrings("text/csv; charset=utf-8", static_mw.detectMime("data.csv"));
    try std.testing.expectEqualStrings("application/vnd.oasis.opendocument.text", static_mw.detectMime("doc.odt"));
    try std.testing.expectEqualStrings("application/vnd.oasis.opendocument.spreadsheet", static_mw.detectMime("sheet.ods"));
    try std.testing.expectEqualStrings("application/vnd.oasis.opendocument.presentation", static_mw.detectMime("slides.odp"));
    try std.testing.expectEqualStrings("application/rtf", static_mw.detectMime("doc.rtf"));
    try std.testing.expectEqualStrings("application/epub+zip", static_mw.detectMime("book.epub"));

    // Archives
    try std.testing.expectEqualStrings("application/x-tar", static_mw.detectMime("archive.tar"));
    try std.testing.expectEqualStrings("application/gzip", static_mw.detectMime("archive.gz"));
    try std.testing.expectEqualStrings("application/x-bzip2", static_mw.detectMime("archive.bz2"));
    try std.testing.expectEqualStrings("application/x-7z-compressed", static_mw.detectMime("archive.7z"));
    try std.testing.expectEqualStrings("application/vnd.rar", static_mw.detectMime("archive.rar"));

    // WASM
    try std.testing.expectEqualStrings("application/wasm", static_mw.detectMime("module.wasm"));

    // Feeds
    try std.testing.expectEqualStrings("application/rss+xml", static_mw.detectMime("feed.rss"));
    try std.testing.expectEqualStrings("application/atom+xml", static_mw.detectMime("feed.atom"));

    // Unknown — text fallback
    try std.testing.expectEqualStrings("application/octet-stream", static_mw.detectMime("data.bin"));
}
