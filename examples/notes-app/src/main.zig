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
const password = zypher.auth.password;
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
    AdminRateLimit.handle,
    zypher.middleware.session.middleware,
    zypher.middleware.csrf.middleware,
    zypher.middleware.security_headers.middleware,
});

fn unixTimestamp() i64 {
    return std.Io.Timestamp.now(tl_io, .real).toSeconds();
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

fn csrfField(req: *Request) ![]u8 {
    return zypher.middleware.csrf.formFieldForRequest(tl_io, req.allocator, req);
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

    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    const cards = html.noteCards(gpa, rows.items, csrf_field) catch {
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

fn archivedHandler(req: *Request, res: *Response) void {
    const ctx = app_context.get();
    const gpa = res.allocator;
    var rows = notes.listArchived(ctx.db, gpa) catch {
        _ = res.status(500);
        res.text("Unable to load archived notes") catch {};
        return;
    };
    defer notes.freeRows(gpa, &rows);

    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    const cards = html.noteCards(gpa, rows.items, csrf_field) catch return;
    defer gpa.free(cards);
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    content.appendSlice(gpa, "<section class=\"toolbar\"><h1>Archive</h1><a class=\"button\" href=\"/notes/new\">New Note</a></section><section class=\"note-grid\">") catch return;
    content.appendSlice(gpa, cards) catch return;
    content.appendSlice(gpa, "</section>") catch return;
    renderLayout(res, "Archived Notes", content.items);
}

fn noteForm(req: *Request, res: *Response, page_title: []const u8, action: []const u8, input: note_domain.NoteInput, err: []const u8) void {
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
    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    ctx.put("csrf_field", .{ .string = csrf_field }) catch {};
    html.render(app_context.get().engine, res, "form.html", &ctx);
}

fn newNoteHandler(req: *Request, res: *Response) void {
    noteForm(req, res, "New Note", "/notes/new", .{ .title = "", .body = "" }, "");
}

fn createNoteHandler(req: *Request, res: *Response) void {
    const input = noteInputFromRequest(req);
    if (input.title.len == 0 or input.body.len == 0) {
        _ = res.status(422);
        noteForm(req, res, "New Note", "/notes/new", input, "Title and body are required.");
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

    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    const content = html.noteView(res.allocator, row, csrf_field) catch {
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
    noteForm(req, res, "Edit Note", action, .{
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
        noteForm(req, res, "Edit Note", action, input, "Title and body are required.");
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

fn loginFormHandler(req: *Request, res: *Response) void {
    var ctx = Context.init(res.allocator);
    defer ctx.deinit();
    ctx.put("error", .{ .string = "" }) catch {};
    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    ctx.put("csrf_field", .{ .string = csrf_field }) catch {};
    html.render(app_context.get().engine, res, "login.html", &ctx);
}

fn loginHandler(req: *Request, res: *Response) void {
    const username = req.formValue("username") orelse "";
    const plain = req.formValue("password") orelse "";
    const db = app_context.get().db;
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT password_hash, role, is_active FROM users WHERE username = ?") catch {
        _ = res.status(401);
        var ctx = Context.init(res.allocator);
        defer ctx.deinit();
        ctx.put("error", .{ .string = "Invalid admin credentials." }) catch {};
        html.render(app_context.get().engine, res, "login.html", &ctx);
        return;
    };
    defer stmt.finalize();
    stmt.bind(.{ .text = username }, 1) catch return;
    if (!(stmt.step() catch false)) return invalidLogin(res);
    const hash = stmt.column(.text, 0) catch return;
    const role = stmt.column(.text, 1) catch return;
    const active = stmt.column(.integer, 2) catch return;
    if (active.int != 1 or !std.mem.eql(u8, role.text, "admin") or !(password.verify(hash.text, plain) catch false)) return invalidLogin(res);

    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        session.put(req.allocator, "username", username) catch {};
        session.put(req.allocator, "role", "admin") catch {};
        app_context.get().sessions.save(session) catch {};
    }
    redirect(res, "/admin/");
}

fn invalidLogin(res: *Response) void {
    _ = res.status(401);
    var ctx = Context.init(res.allocator);
    defer ctx.deinit();
    ctx.put("error", .{ .string = "Invalid admin credentials." }) catch {};
    html.render(app_context.get().engine, res, "login.html", &ctx);
}

fn ensureAuthRecoverySchema(db: *sqlite.Db) void {
    db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  username TEXT NOT NULL UNIQUE,
        \\  email TEXT UNIQUE,
        \\  password_hash TEXT NOT NULL,
        \\  role TEXT NOT NULL DEFAULT 'user',
        \\  is_active INTEGER NOT NULL DEFAULT 1,
        \\  reset_code TEXT,
        \\  reset_code_expires_at INTEGER
        \\)
    ) catch {};
    if (!userColumnExists(db, "email")) db.exec("ALTER TABLE users ADD COLUMN email TEXT") catch {};
    if (!userColumnExists(db, "reset_code")) db.exec("ALTER TABLE users ADD COLUMN reset_code TEXT") catch {};
    if (!userColumnExists(db, "reset_code_expires_at")) db.exec("ALTER TABLE users ADD COLUMN reset_code_expires_at INTEGER") catch {};
}

fn userColumnExists(db: *sqlite.Db, name: []const u8) bool {
    var stmt = db.prepare("PRAGMA table_info(users)") catch return false;
    defer stmt.finalize();
    while (stmt.step() catch false) {
        const column_name = stmt.column(.text, 1) catch continue;
        if (std.mem.eql(u8, column_name.text, name)) return true;
    }
    return false;
}

fn randomBytes(buf: []u8) void {
    tl_io.random(buf);
}

fn generateRecoveryCode(gpa: std.mem.Allocator) ![]u8 {
    var bytes: [4]u8 = undefined;
    randomBytes(&bytes);
    const raw = (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) | (@as(u32, bytes[2]) << 8) | @as(u32, bytes[3]);
    return std.fmt.allocPrint(gpa, "{d:0>6}", .{raw % 1_000_000});
}

fn passwordStrong(plain: []const u8) bool {
    if (plain.len < 8) return false;
    var has_letter = false;
    var has_digit = false;
    for (plain) |ch| {
        if (std.ascii.isAlphabetic(ch)) has_letter = true;
        if (std.ascii.isDigit(ch)) has_digit = true;
    }
    return has_letter and has_digit;
}

fn forgotPasswordFormHandler(req: *Request, res: *Response) void {
    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    const body = std.fmt.allocPrint(req.allocator,
        \\<section class="form-panel">
        \\  <h1>Forgot Password</h1>
        \\  <form method="post" action="/admin/forgot-password">
        \\    {s}
        \\    <label>Email</label>
        \\    <input type="email" name="email">
        \\    <button type="submit">Send Recovery Code</button>
        \\  </form>
        \\</section>
    , .{csrf_field}) catch return;
    defer req.allocator.free(body);
    renderLayout(res, "Forgot Password", body);
}

fn forgotPasswordHandler(req: *Request, res: *Response) void {
    const email = req.formValue("email") orelse "";
    const db = app_context.get().db;
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT username FROM users WHERE email = ? AND role = 'admin' AND is_active = 1") catch {
        renderLayout(res, "Recovery Code", "<p>If an admin account exists for that email, a recovery code was sent.</p>");
        return;
    };
    defer stmt.finalize();
    stmt.bind(.{ .text = email }, 1) catch return;
    if (!(stmt.step() catch false)) {
        renderLayout(res, "Recovery Code", "<p>If an admin account exists for that email, a recovery code was sent.</p>");
        return;
    }
    const code = generateRecoveryCode(req.allocator) catch return;
    defer req.allocator.free(code);
    var update = db.prepare("UPDATE users SET reset_code = ?, reset_code_expires_at = ? WHERE email = ?") catch return;
    defer update.finalize();
    update.bind(.{ .text = code }, 1) catch return;
    update.bind(.{ .int = unixTimestamp() + 900 }, 2) catch return;
    update.bind(.{ .text = email }, 3) catch return;
    _ = update.step() catch return;
    const body = std.fmt.allocPrint(req.allocator,
        \\<section class="form-panel">
        \\  <p>If an admin account exists for {s}, a recovery code was sent.</p>
        \\  <p><a href="/admin/reset-password">Reset password</a></p>
        \\</section>
    , .{email}) catch return;
    defer req.allocator.free(body);
    renderLayout(res, "Recovery Code", body);
}

fn resetPasswordFormHandler(req: *Request, res: *Response) void {
    const csrf_field = csrfField(req) catch "";
    defer if (csrf_field.len > 0) req.allocator.free(csrf_field);
    const body = std.fmt.allocPrint(req.allocator,
        \\<section class="form-panel">
        \\  <h1>Reset Password</h1>
        \\  <form method="post" action="/admin/reset-password">
        \\    {s}
        \\    <label>Email</label>
        \\    <input type="email" name="email">
        \\    <label>Recovery Code</label>
        \\    <input type="text" name="code" inputmode="numeric" maxlength="6">
        \\    <label>New Password</label>
        \\    <input type="password" name="password">
        \\    <label>Confirm Password</label>
        \\    <input type="password" name="confirm_password">
        \\    <button type="submit">Reset Password</button>
        \\  </form>
        \\</section>
    , .{csrf_field}) catch return;
    defer req.allocator.free(body);
    renderLayout(res, "Reset Password", body);
}

fn resetPasswordHandler(req: *Request, res: *Response) void {
    const email = req.formValue("email") orelse "";
    const code = req.formValue("code") orelse "";
    const plain = req.formValue("password") orelse "";
    const confirm = req.formValue("confirm_password") orelse "";
    if (!std.mem.eql(u8, plain, confirm) or !passwordStrong(plain)) {
        _ = res.status(400);
        renderLayout(res, "Reset Password", "<p>Password must match confirmation and include at least 8 characters, a letter, and a digit.</p>");
        return;
    }
    const db = app_context.get().db;
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT reset_code, reset_code_expires_at FROM users WHERE email = ? AND role = 'admin' AND is_active = 1") catch return;
    defer stmt.finalize();
    stmt.bind(.{ .text = email }, 1) catch return;
    if (!(stmt.step() catch false)) {
        _ = res.status(400);
        renderLayout(res, "Reset Password", "<p>Invalid recovery code.</p>");
        return;
    }
    const stored = stmt.column(.text, 0) catch {
        _ = res.status(400);
        renderLayout(res, "Reset Password", "<p>Invalid recovery code.</p>");
        return;
    };
    const expires = stmt.column(.integer, 1) catch {
        _ = res.status(400);
        renderLayout(res, "Reset Password", "<p>Invalid recovery code.</p>");
        return;
    };
    if (expires.int < unixTimestamp() or !std.mem.eql(u8, stored.text, code)) {
        _ = res.status(400);
        renderLayout(res, "Reset Password", "<p>Invalid recovery code.</p>");
        return;
    }
    const hash = password.hash(tl_io, req.allocator, plain) catch return;
    defer req.allocator.free(hash);
    var update = db.prepare("UPDATE users SET password_hash = ?, reset_code = NULL, reset_code_expires_at = NULL WHERE email = ?") catch return;
    defer update.finalize();
    update.bind(.{ .text = hash }, 1) catch return;
    update.bind(.{ .text = email }, 2) catch return;
    _ = update.step() catch return;
    redirect(res, "/admin/login");
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

threadlocal var tl_io: std.Io = undefined;

fn routerDispatch(req: *Request, res: *Response) void {
    app_context.get().router.dispatch(req, res);
}

fn middlewareDispatch(req: *Request, res: *Response) void {
    MiddlewareChain.run(tl_io, req, res, routerDispatch);
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
        .secure = false, // DEV_ONLY: set to true in production
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
        Router.route(.get, "/admin/forgot-password", forgotPasswordFormHandler),
        Router.route(.post, "/admin/forgot-password", forgotPasswordHandler),
        Router.route(.get, "/admin/reset-password", resetPasswordFormHandler),
        Router.route(.post, "/admin/reset-password", resetPasswordHandler),
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

    tl_io = init.io;

    var app = zypher.core.App.init(allocator, .{ .host = "127.0.0.1", .port = parsePort(init) });
    defer app.deinit();
    app.database(&db);
    app.middlewareHandler(middlewareDispatch);

    try app.listenAndServe(init.io);
}

test {
    std.testing.refAllDecls(@This());
}
