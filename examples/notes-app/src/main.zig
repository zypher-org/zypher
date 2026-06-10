const std = @import("std");
const zypher = @import("zypher");

const app_context = @import("app/context.zig");
const note_domain = @import("domain/note.zig");
const notes = @import("persistence/note_repository.zig");
const html = @import("presentation/html.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Route = zypher.router.Route;
const Router = zypher.router.Router;
const Context = zypher.template.renderer.Context;
const Value = zypher.template.renderer.Value;
const Session = zypher.auth.session.Session;
const SessionStore = zypher.auth.session.SessionStore;
const TemplateEngine = zypher.template.renderer.TemplateEngine;
const sqlite = zypher.orm.sqlite;
const AdminSite = zypher.admin.AdminSite;
const Registration = zypher.admin.Registration;

const Admin = AdminSite(.{
    .notes = Registration(note_domain.Note, .{
        .verbose_name_plural = "Notes",
        .list_per_page = 20,
    }),
});

const AdminRateLimit = zypher.middleware.rate_limit.middlewareWith(.{ .max_requests = 240, .window_seconds = 60 });
const MiddlewareChain = zypher.middleware.Chain(.{
    zypher.middleware.logger.middleware,
    zypher.middleware.csrf.middleware,
    AdminRateLimit.handle,
    zypher.middleware.session.middleware,
    zypher.middleware.security_headers.middleware,
});

fn unixTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return ts.sec;
}

fn redirect(res: *Response, location: []const u8) void {
    res.redirect(location, 302) catch {};
}

fn noteInputFromRequest(req: *Request) note_domain.NoteInput {
    return .{
        .title = req.formValue("title") orelse "",
        .body = req.formValue("body") orelse "",
        .tags = req.formValue("tags") orelse "",
        .pinned = req.formValue("pinned") != null,
        .archived = req.formValue("archived") != null,
    };
}

fn renderLayout(res: *Response, title: []const u8, content: []const u8) void {
    var ctx = Context.init(res.allocator);
    defer ctx.deinit();
    ctx.put("title", .{ .string = title }) catch {};
    ctx.put("content", .{ .string = content }) catch {};
    html.render(app_context.get().engine, res, "layout.html", &ctx);
}

fn listHandler(req: *Request, res: *Response) void {
    const ctx = app_context.get();
    const gpa = res.allocator;
    const search_term = req.queryParam("q") orelse "";

    var rows = if (search_term.len > 0)
        notes.search(ctx.db, gpa, search_term) catch {
            _ = res.status(500);
            res.text("Unable to search notes") catch {};
            return;
        }
    else
        notes.listActive(ctx.db, gpa) catch {
            _ = res.status(500);
            res.text("Unable to load notes") catch {};
            return;
        };
    defer notes.freeRows(gpa, &rows);

    const cards = html.noteCards(gpa, rows.items) catch {
        _ = res.status(500);
        res.text("Unable to render notes") catch {};
        return;
    };
    defer gpa.free(cards);
    const safe_search = html.htmlEscape(gpa, search_term) catch {
        _ = res.status(500);
        res.text("Unable to render search term") catch {};
        return;
    };
    defer gpa.free(safe_search);

    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    content.appendSlice(gpa, "<section class=\"toolbar\"><h1>Notes</h1><form method=\"get\" action=\"/\"><input name=\"q\" placeholder=\"Search notes\" value=\"") catch return;
    content.appendSlice(gpa, safe_search) catch return;
    content.appendSlice(gpa, "\"><button>Search</button></form><a class=\"button\" href=\"/notes/new\">New Note</a></section><section class=\"note-grid\">") catch return;
    content.appendSlice(gpa, cards) catch return;
    content.appendSlice(gpa, "</section>") catch return;
    renderLayout(res, "Notes", content.items);
}

fn archivedHandler(_: *Request, res: *Response) void {
    const ctx = app_context.get();
    const gpa = res.allocator;
    var rows = notes.listArchived(ctx.db, gpa) catch {
        _ = res.status(500);
        res.text("Unable to load archived notes") catch {};
        return;
    };
    defer notes.freeRows(gpa, &rows);

    const cards = html.noteCards(gpa, rows.items) catch return;
    defer gpa.free(cards);
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    content.appendSlice(gpa, "<section class=\"toolbar\"><h1>Archive</h1><a class=\"button\" href=\"/notes/new\">New Note</a></section><section class=\"note-grid\">") catch return;
    content.appendSlice(gpa, cards) catch return;
    content.appendSlice(gpa, "</section>") catch return;
    renderLayout(res, "Archived Notes", content.items);
}

fn noteForm(res: *Response, page_title: []const u8, action: []const u8, input: note_domain.NoteInput, err: []const u8) void {
    var ctx = Context.init(res.allocator);
    defer ctx.deinit();
    ctx.put("page_title", .{ .string = page_title }) catch {};
    ctx.put("action", .{ .string = action }) catch {};
    ctx.put("title_value", .{ .string = input.title }) catch {};
    ctx.put("body_value", .{ .string = input.body }) catch {};
    ctx.put("tags_value", .{ .string = input.tags }) catch {};
    ctx.put("pinned_checked", .{ .string = if (input.pinned) "checked" else "" }) catch {};
    ctx.put("archived_checked", .{ .string = if (input.archived) "checked" else "" }) catch {};
    ctx.put("error", .{ .string = err }) catch {};
    html.render(app_context.get().engine, res, "form.html", &ctx);
}

fn newNoteHandler(_: *Request, res: *Response) void {
    noteForm(res, "New Note", "/notes/new", .{ .title = "", .body = "" }, "");
}

fn createNoteHandler(req: *Request, res: *Response) void {
    const input = noteInputFromRequest(req);
    if (input.title.len == 0 or input.body.len == 0) {
        _ = res.status(422);
        noteForm(res, "New Note", "/notes/new", input, "Title and body are required.");
        return;
    }
    const id = notes.create(app_context.get().db, input, unixTimestamp()) catch {
        _ = res.status(500);
        res.text("Unable to create note") catch {};
        return;
    };
    var location_buf: [64]u8 = undefined;
    const location = std.fmt.bufPrint(&location_buf, "/notes/{d}", .{id}) catch "/";
    redirect(res, location);
}

fn viewNoteHandler(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    var row = notes.get(app_context.get().db, res.allocator, id) catch {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    defer notes.freeRow(res.allocator, &row);

    const content = html.noteView(res.allocator, row) catch {
        _ = res.status(500);
        res.text("Unable to render note") catch {};
        return;
    };
    defer res.allocator.free(content);
    renderLayout(res, row[1], content);
}

fn editNoteHandler(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    var row = notes.get(app_context.get().db, res.allocator, id) catch {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    defer notes.freeRow(res.allocator, &row);

    var action_buf: [80]u8 = undefined;
    const action = std.fmt.bufPrint(&action_buf, "/notes/{d}/edit", .{id}) catch "/";
    noteForm(res, "Edit Note", action, .{
        .title = row[1],
        .body = row[2],
        .tags = row[3],
        .pinned = row[4],
        .archived = row[5],
    }, "");
}

fn updateNoteHandler(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    const input = noteInputFromRequest(req);
    if (input.title.len == 0 or input.body.len == 0) {
        _ = res.status(422);
        var action_buf: [80]u8 = undefined;
        const action = std.fmt.bufPrint(&action_buf, "/notes/{d}/edit", .{id}) catch "/";
        noteForm(res, "Edit Note", action, input, "Title and body are required.");
        return;
    }
    notes.update(app_context.get().db, id, input, unixTimestamp()) catch {
        _ = res.status(500);
        res.text("Unable to update note") catch {};
        return;
    };
    var location_buf: [64]u8 = undefined;
    const location = std.fmt.bufPrint(&location_buf, "/notes/{d}", .{id}) catch "/";
    redirect(res, location);
}

fn archiveNoteHandler(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch return;
    notes.archive(app_context.get().db, req.allocator, id, true, unixTimestamp()) catch {};
    redirect(res, "/");
}

fn restoreNoteHandler(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch return;
    notes.archive(app_context.get().db, req.allocator, id, false, unixTimestamp()) catch {};
    redirect(res, "/archived");
}

fn deleteNoteHandler(req: *Request, res: *Response) void {
    const id = req.params.getAs(i64, "id") catch return;
    notes.delete(app_context.get().db, id) catch {};
    redirect(res, "/");
}

fn loginFormHandler(_: *Request, res: *Response) void {
    var ctx = Context.init(res.allocator);
    defer ctx.deinit();
    ctx.put("error", .{ .string = "" }) catch {};
    html.render(app_context.get().engine, res, "login.html", &ctx);
}

fn loginHandler(req: *Request, res: *Response) void {
    const username = req.formValue("username") orelse "";
    const password = req.formValue("password") orelse "";
    if (!std.mem.eql(u8, username, "admin") or !std.mem.eql(u8, password, "admin123")) {
        _ = res.status(401);
        var ctx = Context.init(res.allocator);
        defer ctx.deinit();
        ctx.put("error", .{ .string = "Invalid admin credentials." }) catch {};
        html.render(app_context.get().engine, res, "login.html", &ctx);
        return;
    }

    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        session.put(req.allocator, "username", "admin") catch {};
        session.put(req.allocator, "role", "admin") catch {};
        app_context.get().sessions.save(session) catch {};
    }
    redirect(res, "/admin/");
}

fn logoutHandler(req: *Request, res: *Response) void {
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        app_context.get().sessions.destroy(session.id) catch {};
    }
    _ = res.deleteCookie("zypher_session");
    redirect(res, "/");
}

fn notFoundHandler(_: *Request, res: *Response) void {
    _ = res.status(404);
    renderLayout(res, "Not Found", "<section class=\"empty\"><h1>Not Found</h1><p>The requested page does not exist.</p></section>");
}

fn routerDispatch(req: *Request, res: *Response) void {
    app_context.get().router.dispatch(req, res);
}

fn middlewareDispatch(req: *Request, res: *Response) void {
    MiddlewareChain.run(req, res, routerDispatch);
}

fn parsePort(init: std.process.Init) u16 {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--port")) {
            const raw = args.next() orelse return 8080;
            return std.fmt.parseInt(u16, raw, 10) catch 8080;
        }
    }
    return 8080;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var db = try sqlite.Db.open(allocator, "notes_app.db");
    errdefer db.close();
    try notes.migrate(&db);

    var engine = TemplateEngine.init(allocator);
    defer engine.deinit();
    try html.loadTemplates(&engine);
    Admin.loadTemplates(&engine);

    var sessions = SessionStore.init(allocator);
    defer sessions.deinit();
    zypher.middleware.session.setStore(&sessions);
    zypher.middleware.session.setCookieConfig(.{
        .httponly = true,
        .secure = false,
        .samesite = "Strict",
        .path = "/",
        .max_age = 86400,
    });

    const admin_routes = Admin.routes();
    const app_routes = [_]Route{
        Router.route(.get, "/", listHandler),
        Router.route(.get, "/archived", archivedHandler),
        Router.route(.get, "/notes/new", newNoteHandler),
        Router.route(.post, "/notes/new", createNoteHandler),
        Router.route(.get, "/notes/:id", viewNoteHandler),
        Router.route(.get, "/notes/:id/edit", editNoteHandler),
        Router.route(.post, "/notes/:id/edit", updateNoteHandler),
        Router.route(.post, "/notes/:id/archive", archiveNoteHandler),
        Router.route(.post, "/notes/:id/restore", restoreNoteHandler),
        Router.route(.post, "/notes/:id/delete", deleteNoteHandler),
        Router.route(.get, "/admin/login", loginFormHandler),
        Router.route(.post, "/admin/login", loginHandler),
        Router.route(.post, "/logout", logoutHandler),
    };
    const routes = app_routes ++ admin_routes;
    var router = Router.initFromSlice(&routes, notFoundHandler);

    var ctx = app_context.AppContext{
        .db = &db,
        .engine = &engine,
        .sessions = &sessions,
        .router = &router,
    };
    app_context.set(&ctx);
    zypher.admin.setDb(&db);
    zypher.admin.setEngine(&engine);

    var app = zypher.core.App.init(allocator, .{ .host = "127.0.0.1", .port = parsePort(init) });
    defer app.deinit();
    app.database(&db);
    app.middlewareHandler(middlewareDispatch);

    try app.listenAndServe(init.io);
}

test {
    std.testing.refAllDecls(@This());
}
