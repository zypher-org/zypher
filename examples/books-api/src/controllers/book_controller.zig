const std = @import("std");
const zypher = @import("zypher");
const context = @import("../app/context.zig");
const book = @import("../models/book.zig");
const view = @import("../views/book_view.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;

fn unixTimestamp() i64 {
    return std.Io.Timestamp.now(context.io(), .real).toSeconds();
}

fn input(req: *Request) book.BookInput {
    return .{
        .title = req.formValue("title") orelse "",
        .author = req.formValue("author") orelse "",
        .year = if (req.formValue("year")) |raw| std.fmt.parseInt(i64, raw, 10) catch 0 else 0,
    };
}

fn sendJson(res: *Response, body: []const u8) void {
    res.json(body) catch {
        _ = res.status(500);
    };
}

pub fn list(_: *Request, res: *Response) void {
    var rows = book.list(context.db(), res.allocator) catch {
        _ = res.status(500);
        return sendJson(res, "{\"error\":\"load_failed\"}");
    };
    defer book.freeRows(res.allocator, &rows);
    const body = view.listJson(res.allocator, rows.items) catch return;
    defer res.allocator.free(body);
    sendJson(res, body);
}

pub fn show(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch {
        _ = res.status(404);
        return sendJson(res, "{\"error\":\"not_found\"}");
    };
    var row = book.get(context.db(), res.allocator, id) catch {
        _ = res.status(404);
        return sendJson(res, "{\"error\":\"not_found\"}");
    };
    defer book.freeRow(res.allocator, &row);
    const body = view.bookJson(res.allocator, row) catch return;
    defer res.allocator.free(body);
    sendJson(res, body);
}

pub fn create(req: *Request, res: *Response) void {
    const data = input(req);
    if (data.title.len == 0 or data.author.len == 0) {
        _ = res.status(422);
        return sendJson(res, "{\"error\":\"title_and_author_required\"}");
    }
    const id = book.create(context.db(), data, unixTimestamp()) catch {
        _ = res.status(500);
        return sendJson(res, "{\"error\":\"create_failed\"}");
    };
    var row = book.get(context.db(), res.allocator, id) catch return;
    defer book.freeRow(res.allocator, &row);
    _ = res.status(201);
    const body = view.bookJson(res.allocator, row) catch return;
    defer res.allocator.free(body);
    sendJson(res, body);
}

pub fn update(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch {
        _ = res.status(404);
        return sendJson(res, "{\"error\":\"not_found\"}");
    };
    var row = book.get(context.db(), res.allocator, id) catch {
        _ = res.status(404);
        return sendJson(res, "{\"error\":\"not_found\"}");
    };
    defer book.freeRow(res.allocator, &row);
    const data = input(req);
    if (data.title.len == 0 or data.author.len == 0) {
        _ = res.status(422);
        return sendJson(res, "{\"error\":\"title_and_author_required\"}");
    }
    book.update(context.db(), id, data, row[4]) catch {
        _ = res.status(500);
        return sendJson(res, "{\"error\":\"update_failed\"}");
    };
    sendJson(res, "{\"message\":\"updated\"}");
}

pub fn delete(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch {
        _ = res.status(404);
        return sendJson(res, "{\"error\":\"not_found\"}");
    };
    book.delete(context.db(), id) catch {
        _ = res.status(404);
        return sendJson(res, "{\"error\":\"not_found\"}");
    };
    sendJson(res, "{\"message\":\"deleted\"}");
}
