const std = @import("std");
const zypher = @import("zypher");

const schema = zypher.orm.schema;
const Field = schema.Field;
const Model = schema.Model;
const query = zypher.orm.query;
const sqlite = zypher.orm.sqlite;
const Router = zypher.router.Router;
const Route = zypher.router.Route;
const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Method = zypher.core.Method;
const Chain = zypher.middleware.Chain;
const TemplateEngine = zypher.template.renderer.TemplateEngine;
const Context = zypher.template.renderer.Context;
const Value = zypher.template.renderer.Value;
const SessionStore = zypher.auth.session.SessionStore;
const Session = zypher.auth.session.Session;
const password = zypher.auth.password;
const form = zypher.forms.form;
const csrf = zypher.middleware.csrf;
const AdminSite = zypher.admin.AdminSite;
const Registration = zypher.admin.Registration;

// ── Models ────────────────────────────────────────────────────────────────

const PostFields = struct {
    id: schema.FieldDef = Field("id", .integer, .{ .primary = true }),
    title: schema.FieldDef = Field("title", .text, .{ .required = true }),
    body: schema.FieldDef = Field("body", .text, .{ .required = true }),
    author: schema.FieldDef = Field("author", .text, .{ .required = true }),
    created_at: schema.FieldDef = Field("created_at", .integer, .{ .required = true }),
};
pub const Post = Model("posts", PostFields);

const CommentFields = struct {
    id: schema.FieldDef = Field("id", .integer, .{ .primary = true }),
    post_id: schema.FieldDef = Field("post_id", .integer, .{ .required = true }),
    author: schema.FieldDef = Field("author", .text, .{ .required = true }),
    body: schema.FieldDef = Field("body", .text, .{ .required = true }),
    created_at: schema.FieldDef = Field("created_at", .integer, .{ .required = true }),
};
pub const Comment = Model("comments", CommentFields);

// ── Forms ────────────────────────────────────────────────────────────────

const PostFormFields = struct {
    title: form.FieldDef = form.Field("title", .text, .{ .required = true }),
    body: form.FieldDef = form.Field("body", .text, .{ .required = true }),
};
pub const PostForm = form.Form("PostForm", PostFormFields);

const CommentFormFields = struct {
    body: form.FieldDef = form.Field("body", .text, .{ .required = true }),
};
pub const CommentForm = form.Form("CommentForm", CommentFormFields);

pub const middleware_names = [_][]const u8{ "logger", "csrf", "rate-limit", "session" };

pub const FeatureContract = struct {
    pub const hasPostModel = true;
    pub const hasCommentModel = true;
    pub const hasRegisterLoginLogout = true;
    pub const hasAdminPostAndComment = true;
    pub const hasPostAndCommentViews = true;
    pub const hasPostAndCommentForms = true;
};

// ── Admin Registration ────────────────────────────────────────────────────

pub const Site = AdminSite(.{
    .posts = Registration(Post, .{ .verbose_name_plural = "Posts" }),
    .comments = Registration(Comment, .{ .verbose_name_plural = "Comments" }),
});

// ── Thread-local shared state ─────────────────────────────────────────────

threadlocal var tldb: ?*sqlite.Db = null;
threadlocal var tlengine: ?*TemplateEngine = null;
threadlocal var tlstore: ?*SessionStore = null;
threadlocal var tlrouter: ?*const Router = null;

// ── Utilities ─────────────────────────────────────────────────────────────

fn unixTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return ts.sec;
}

fn eng() *TemplateEngine {
    return tlengine orelse @panic("demo: no engine");
}

fn getSessionUser(req: *const Request) ?struct { username: []const u8, role: []const u8 } {
    const user_ptr = req.user orelse return null;
    const session: *Session = @ptrCast(@alignCast(user_ptr));
    const username = session.get("username") orelse return null;
    const role = session.get("role") orelse "user";
    return .{ .username = username, .role = role };
}

fn writeHtml(res: *Response, content: []const u8) void {
    if (res.body) |old| res.allocator.free(old);
    res.body = res.allocator.dupe(u8, content) catch return;
    _ = res.header("Content-Type", "text/html; charset=utf-8");
}

fn renderPage(res: *Response, ctx: *Context) void {
    const gpa = res.allocator;
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    eng().render("base.html", ctx, &aw.writer) catch {
        std.log.err("renderPage: render failed", .{});
        _ = res.status(500);
        return;
    };
    var buf = aw.toArrayList();
    const owned = buf.toOwnedSlice(gpa) catch {
        std.log.err("renderPage: toOwnedSlice failed", .{});
        _ = res.status(500);
        return;
    };
    writeHtml(res, owned);
    std.log.info("renderPage: body after writeHtml={any}", .{if (res.body) |b| b.len else 0});
    gpa.free(owned);
}

fn setupContext(req: *const Request, ctx: *Context, title: []const u8) void {
    ctx.put("title", .{ .string = title }) catch {};
    const user = getSessionUser(req);
    ctx.put("authenticated", .{ .bool = user != null }) catch {};
    ctx.put("username", .{ .string = if (user) |u| u.username else "" }) catch {};
    ctx.put("flash", .{ .string = "" }) catch {};
    ctx.put("flash_type", .{ .string = "" }) catch {};
    ctx.put("content", .{ .string = "" }) catch {};
}

fn intStr(buf: []u8, n: i64) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch "0";
}

fn escHtml(gpa: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.indexOfAny(u8, s, "&<>\"'") == null) return s;
    var buf = std.ArrayList(u8).init(gpa);
    for (s) |c| switch (c) {
        '&' => try buf.appendSlice("&amp;"),
        '<' => try buf.appendSlice("&lt;"),
        '>' => try buf.appendSlice("&gt;"),
        '"' => try buf.appendSlice("&quot;"),
        '\'' => try buf.appendSlice("&#x27;"),
        else => try buf.append(c),
    };
    return buf.toOwnedSlice(gpa);
}

fn redirect(res: *Response, url: []const u8) void {
    _ = res.status(302);
    _ = res.header("Location", url);
}

fn appendCsrfInput(gpa: std.mem.Allocator, html: *std.ArrayList(u8)) !void {
    try html.appendSlice(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"");
    try html.appendSlice(gpa, csrf.generateToken());
    try html.appendSlice(gpa, "\">");
}

// ── Handlers ──────────────────────────────────────────────────────────────

fn indexHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    const d = tldb orelse {
        std.log.err("indexHandler: no database", .{});
        _ = res.status(500);
        res.text("no database") catch {};
        return;
    };

    var rows = query.all(Post, d, gpa) catch {
        _ = res.status(500);
        res.text("query failed") catch {};
        return;
    };
    defer {
        for (rows.items) |*r| query.freeRow(Post, gpa, r);
        rows.deinit(gpa);
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(gpa);
    // Build using direct appends
    html.appendSlice(gpa, "<h1>Posts</h1>\n") catch return;

    if (rows.items.len == 0) {
        html.appendSlice(gpa, "<p>No posts yet. <a href=\"/post/new\">Create one!</a></p>\n") catch return;
    } else {
        for (rows.items) |row| {
            html.appendSlice(gpa, "<div class=\"post\">\n<h2><a href=\"/post/") catch return;
            var id_buf: [32]u8 = undefined;
            html.appendSlice(gpa, intStr(&id_buf, row[0])) catch return;
            html.appendSlice(gpa, "\">") catch return;
            html.appendSlice(gpa, row[1]) catch return; // title
            html.appendSlice(gpa, "</a></h2>\n<div class=\"meta\">by ") catch return;
            html.appendSlice(gpa, row[3]) catch return; // author
            html.appendSlice(gpa, " &middot; ") catch return;
            var ts_buf: [32]u8 = undefined;
            html.appendSlice(gpa, intStr(&ts_buf, row[4])) catch return; // created_at
            html.appendSlice(gpa, "</div>\n<p>") catch return;
            const body = row[2];
            if (body.len > 200) {
                html.appendSlice(gpa, body[0..200]) catch return;
                html.appendSlice(gpa, "&hellip;") catch return;
            } else {
                html.appendSlice(gpa, body) catch return;
            }
            html.appendSlice(gpa, "</p>\n</div>\n") catch return;
        }
    }

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    setupContext(req, &ctx, "Posts — zypher Demo");
    ctx.put("content", .{ .string = html.items }) catch {};
    renderPage(res, &ctx);
}

fn newPostFormHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    if (getSessionUser(req) == null) {
        redirect(res, "/login");
        return;
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(gpa);
    html.appendSlice(gpa,
        \\<h1>New Post</h1>
        \\<form method="post" action="/post/new">
    ) catch return;
    appendCsrfInput(gpa, &html) catch return;
    html.appendSlice(gpa,
        \\<label>Title: <input type="text" name="title" required></label>
        \\<label>Body: <textarea name="body" rows="10" required></textarea></label>
        \\<button type="submit">Create Post</button>
        \\</form>
    ) catch return;

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    setupContext(req, &ctx, "New Post — zypher Demo");
    ctx.put("content", .{ .string = html.items }) catch {};
    renderPage(res, &ctx);
}

fn createPostHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    const user = getSessionUser(req) orelse {
        redirect(res, "/login");
        return;
    };
    const d = tldb orelse {
        _ = res.status(500);
        res.text("no database") catch {};
        return;
    };

    var form_data = std.StringHashMap([]const u8).init(gpa);
    defer form_data.deinit();
    if (req.formValue("title")) |title| form_data.put("title", title) catch {};
    if (req.formValue("body")) |body| form_data.put("body", body) catch {};
    var bound = PostForm.bind(gpa, &form_data) catch {
        _ = res.status(500);
        res.text("form bind failed") catch {};
        return;
    };
    defer bound.deinit();
    if (!bound.validate()) {
        _ = res.status(400);
        res.text("title and body required") catch {};
        return;
    }
    const cleaned = bound.cleanedData();
    const title = cleaned[0];
    const body = cleaned[1];

    const now = unixTimestamp();
    const row_id = query.create(Post, d, &.{
        sqlite.Value{ .text = title },
        sqlite.Value{ .text = body },
        sqlite.Value{ .text = user.username },
        sqlite.Value{ .int = now },
    }) catch {
        _ = res.status(500);
        res.text("create failed") catch {};
        return;
    };

    var id_buf: [32]u8 = undefined;
    var loc: [128]u8 = undefined;
    const loc_str = std.fmt.bufPrint(&loc, "/post/{s}", .{intStr(&id_buf, row_id)}) catch "/";
    redirect(res, loc_str);
}

fn postDetailHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    const d = tldb orelse {
        _ = res.status(500);
        res.text("no database") catch {};
        return;
    };

    const id_str = req.params.get("id") orelse {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    const post_id = std.fmt.parseInt(i64, id_str, 10) catch {
        _ = res.status(404);
        res.text("Invalid ID") catch {};
        return;
    };

    const post_row = query.getById(Post, d, gpa, post_id) catch {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    defer query.freeRow(Post, gpa, @constCast(&post_row));

    var comments = query.filter(Comment, d, gpa, "post_id = ?", &.{.{ .int = post_id }}) catch {
        _ = res.status(500);
        res.text("query failed") catch {};
        return;
    };
    defer {
        for (comments.items) |*r| query.freeRow(Comment, gpa, r);
        comments.deinit(gpa);
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(gpa);

    // Post
    html.appendSlice(gpa, "<div class=\"post\">\n<h1>") catch return;
    html.appendSlice(gpa, post_row[1]) catch return; // title
    html.appendSlice(gpa, "</h1>\n<div class=\"meta\">by ") catch return;
    html.appendSlice(gpa, post_row[3]) catch return; // author
    html.appendSlice(gpa, " &middot; ") catch return;
    var ts_buf: [32]u8 = undefined;
    html.appendSlice(gpa, intStr(&ts_buf, post_row[4])) catch return; // created_at
    html.appendSlice(gpa, "</div>\n<div>") catch return;
    html.appendSlice(gpa, post_row[2]) catch return; // body
    html.appendSlice(gpa, "</div>\n</div>\n") catch return;

    // Comments
    html.appendSlice(gpa, "<h2>Comments</h2>\n") catch return;
    if (comments.items.len == 0) {
        html.appendSlice(gpa, "<p>No comments yet.</p>\n") catch return;
    } else {
        for (comments.items) |c| {
            html.appendSlice(gpa, "<div class=\"comment\">\n<strong>") catch return;
            html.appendSlice(gpa, c[2]) catch return; // author
            html.appendSlice(gpa, "</strong> &middot; ") catch return;
            var cts: [32]u8 = undefined;
            html.appendSlice(gpa, intStr(&cts, c[4])) catch return; // created_at
            html.appendSlice(gpa, "\n<div>") catch return;
            html.appendSlice(gpa, c[3]) catch return; // body
            html.appendSlice(gpa, "</div>\n</div>\n") catch return;
        }
    }

    // Comment form
    const user = getSessionUser(req);
    if (user != null) {
        html.appendSlice(gpa,
            \\<h3>Add a Comment</h3>
            \\<form method="post" action="/post/
        ) catch return;
        html.appendSlice(gpa, id_str) catch return;
        html.appendSlice(gpa,
            \\/comment">
        ) catch return;
        appendCsrfInput(gpa, &html) catch return;
        html.appendSlice(gpa,
            \\<label>Comment: <textarea name="body" rows="3" required></textarea></label>
            \\<button type="submit">Submit</button>
            \\</form>
        ) catch return;
    } else {
        html.appendSlice(gpa, "<p><a href=\"/login\">Log in</a> to comment.</p>\n") catch return;
    }

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    var title_buf: [256]u8 = undefined;
    const title_str = std.fmt.bufPrint(&title_buf, "{s} — zypher Demo", .{post_row[1]}) catch "Post";
    setupContext(req, &ctx, title_str);
    ctx.put("content", .{ .string = html.items }) catch {};
    renderPage(res, &ctx);
}

fn addCommentHandler(req: *Request, res: *Response) void {
    const user = getSessionUser(req) orelse {
        redirect(res, "/login");
        return;
    };
    const d = tldb orelse {
        _ = res.status(500);
        res.text("no database") catch {};
        return;
    };

    const id_str = req.params.get("id") orelse {
        _ = res.status(404);
        res.text("Not Found") catch {};
        return;
    };
    const post_id = std.fmt.parseInt(i64, id_str, 10) catch {
        _ = res.status(404);
        res.text("Invalid ID") catch {};
        return;
    };

    var form_data = std.StringHashMap([]const u8).init(req.allocator);
    defer form_data.deinit();
    if (req.formValue("body")) |body_value| form_data.put("body", body_value) catch {};
    var bound = CommentForm.bind(req.allocator, &form_data) catch {
        _ = res.status(500);
        res.text("form bind failed") catch {};
        return;
    };
    defer bound.deinit();
    if (!bound.validate()) {
        _ = res.status(400);
        res.text("body required") catch {};
        return;
    }
    const body = bound.cleanedData()[0];

    _ = query.create(Comment, d, &.{
        sqlite.Value{ .int = post_id },
        sqlite.Value{ .text = user.username },
        sqlite.Value{ .text = body },
        sqlite.Value{ .int = unixTimestamp() },
    }) catch {
        _ = res.status(500);
        res.text("create failed") catch {};
        return;
    };

    var loc_buf: [128]u8 = undefined;
    const loc = std.fmt.bufPrint(&loc_buf, "/post/{s}", .{id_str}) catch "/";
    redirect(res, loc);
}

fn registerFormHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    if (getSessionUser(req) != null) {
        redirect(res, "/");
        return;
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(gpa);
    html.appendSlice(gpa,
        \\<h1>Register</h1>
        \\<form method="post" action="/register">
    ) catch return;
    appendCsrfInput(gpa, &html) catch return;
    html.appendSlice(gpa,
        \\<label>Username: <input type="text" name="username" required></label>
        \\<label>Password: <input type="password" name="password" required></label>
        \\<button type="submit">Register</button>
        \\</form>
        \\<p>Already have an account? <a href="/login">Log in</a></p>
    ) catch return;

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    setupContext(req, &ctx, "Register — zypher Demo");
    ctx.put("content", .{ .string = html.items }) catch {};
    renderPage(res, &ctx);
}

fn registerHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    if (getSessionUser(req) != null) {
        redirect(res, "/");
        return;
    }
    const d = tldb orelse {
        _ = res.status(500);
        res.text("no database") catch {};
        return;
    };

    const username = req.formValue("username") orelse "";
    const pass = req.formValue("password") orelse "";
    if (username.len < 3 or pass.len < 3) {
        _ = res.status(400);
        res.text("username and password must be at least 3 characters") catch {};
        return;
    }

    // Hash password
    const hash = password.hash(gpa, pass) catch {
        _ = res.status(500);
        res.text("password hashing failed") catch {};
        return;
    };
    defer gpa.free(hash);

    // Insert user
    const insert_sql = "INSERT INTO users (username, password_hash, role, is_active) VALUES (?, ?, 'user', 1)";
    var stmt = d.prepare(insert_sql) catch {
        _ = res.status(500);
        res.text("prepare failed") catch {};
        return;
    };
    defer stmt.finalize();
    stmt.bind(.{ .text = username }, 1) catch {
        _ = res.status(500);
        res.text("bind failed") catch {};
        return;
    };
    stmt.bind(.{ .text = hash }, 2) catch {
        _ = res.status(500);
        res.text("bind failed") catch {};
        return;
    };
    _ = stmt.step() catch |err| {
        if (err == error.ConstraintViolation) {
            _ = res.status(409);
            res.text("username already taken") catch {};
        } else {
            _ = res.status(500);
            res.text("insert failed") catch {};
        }
        return;
    };

    // Log the user in by setting session data
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        session.put(gpa, "username", username) catch {};
        session.put(gpa, "role", "user") catch {};
        // Save to persist the session data
        const s = tlstore orelse return;
        s.save(session) catch {};
    }

    redirect(res, "/");
}

fn loginFormHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    if (getSessionUser(req) != null) {
        redirect(res, "/");
        return;
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(gpa);
    html.appendSlice(gpa,
        \\<h1>Login</h1>
        \\<form method="post" action="/login">
    ) catch return;
    appendCsrfInput(gpa, &html) catch return;
    html.appendSlice(gpa,
        \\<label>Username: <input type="text" name="username" required></label>
        \\<label>Password: <input type="password" name="password" required></label>
        \\<button type="submit">Log In</button>
        \\</form>
        \\<p>Don't have an account? <a href="/register">Register</a></p>
    ) catch return;

    var ctx = Context.init(gpa);
    defer ctx.deinit();
    setupContext(req, &ctx, "Login — zypher Demo");
    ctx.put("content", .{ .string = html.items }) catch {};
    renderPage(res, &ctx);
}

fn loginHandler(req: *Request, res: *Response) void {
    const gpa = res.allocator;
    if (getSessionUser(req) != null) {
        redirect(res, "/");
        return;
    }
    const d = tldb orelse {
        _ = res.status(500);
        res.text("no database") catch {};
        return;
    };

    const username = req.formValue("username") orelse "";
    const pass = req.formValue("password") orelse "";

    // Look up user
    var stmt = d.prepare("SELECT password_hash, role FROM users WHERE username = ?") catch {
        _ = res.status(500);
        res.text("database error") catch {};
        return;
    };
    defer stmt.finalize();

    stmt.bind(.{ .text = username }, 1) catch {
        _ = res.status(500);
        res.text("bind error") catch {};
        return;
    };

    const has_row = stmt.step() catch {
        _ = res.status(500);
        res.text("query error") catch {};
        return;
    };

    if (!has_row) {
        _ = res.status(401);
        res.text("Invalid username or password") catch {};
        return;
    }

    const hash_val = stmt.column(.text, 0) catch {
        _ = res.status(500);
        res.text("read hash failed") catch {};
        return;
    };
    const role_val = stmt.column(.text, 1) catch {
        _ = res.status(500);
        res.text("read role failed") catch {};
        return;
    };
    const stored_hash = hash_val.text;
    const role = role_val.text;

    // Verify password
    const valid = password.verify(stored_hash, pass) catch {
        _ = res.status(500);
        res.text("password verification error") catch {};
        return;
    };
    if (!valid) {
        _ = res.status(401);
        res.text("Invalid username or password") catch {};
        return;
    }

    // Set session data
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        session.put(gpa, "username", username) catch {};
        session.put(gpa, "role", role) catch {};
        const s = tlstore orelse return;
        s.save(session) catch {};
    }

    redirect(res, "/");
}

fn logoutHandler(req: *Request, res: *Response) void {
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        if (tlstore) |s| {
            s.destroy(session.id) catch {};
        }
        req.user = null;
    }
    _ = res.deleteCookie("zypher_session");
    redirect(res, "/");
}

fn notFoundHandler(req: *Request, res: *Response) void {
    _ = req;
    _ = res.status(404);
    res.text("Not Found") catch {};
}

// ── Middleware ─────────────────────────────────────────────────────────────

fn loggerMw(req: *Request, res: *Response, next: *const fn (*Request, *Response) void) void {
    std.log.info("→ {s} {s}", .{ @tagName(req.method), req.path });
    next(req, res);
    std.log.info("← {d}", .{res.status_code});
}

const DemoRateLimit = zypher.middleware.rate_limit.middlewareWith(.{ .max_requests = 100, .window_seconds = 60 });
const MwChain = Chain(.{ loggerMw, zypher.middleware.csrf.middleware, DemoRateLimit.handle, zypher.middleware.session.middleware });

fn dispatchWrapper(req: *Request, res: *Response) void {
    const r = tlrouter orelse return;
    r.dispatch(req, res);
}

fn mwHandler(req: *Request, res: *Response) void {
    MwChain.run(req, res, dispatchWrapper);
}

// ── Main ──────────────────────────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // ── Database ───────────────────────────────────────────────────────
    var db = try sqlite.Db.open(allocator, "zypher_demo.db");
    errdefer db.close();
    try db.exec(Post.create_table_sql);
    try db.exec(Comment.create_table_sql);
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  username TEXT NOT NULL UNIQUE,
        \\  password_hash TEXT NOT NULL,
        \\  role TEXT NOT NULL DEFAULT 'user',
        \\  is_active INTEGER NOT NULL DEFAULT 1
        \\)
    );
    tldb = &db;

    // ── Template Engine ────────────────────────────────────────────────
    var engine = TemplateEngine.init(allocator);
    defer engine.deinit();
    _ = try engine.load("base.html",
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>{{ title }}</title>
        \\    <meta name="viewport" content="width=device-width">
        \\    <style>
        \\        *{box-sizing:border-box}body{font-family:system-ui,sans-serif;max-width:800px;margin:0 auto;padding:0 1em}
        \\        nav{border-bottom:2px solid #eee;padding:1em 0;margin-bottom:1em}
        \\        nav a{margin-right:1em;color:#0366d6;text-decoration:none}
        \\        nav a:hover{text-decoration:underline}
        \\        nav form{display:inline}nav button{background:none;border:none;color:#0366d6;cursor:pointer;padding:0;font:inherit;text-decoration:underline}
        \\        .flash{padding:.5em 1em;border-radius:4px;margin-bottom:1em}
        \\        .flash-error{background:#ffeef0;color:#d73a49}
        \\        .flash-success{background:#dcffe4;color:#22863a}
        \\        .post{border:1px solid #eee;padding:1em;margin-bottom:1em;border-radius:4px}
        \\        .post h2{margin:0 0 .5em 0}.post h2 a{color:inherit;text-decoration:none}
        \\        .post .meta{color:#666;font-size:.9em}
        \\        .comment{border-left:3px solid #eee;padding-left:1em;margin:.5em 0;font-size:.95em}
        \\        label{display:block;margin:.5em 0;font-weight:600}
        \\        input,textarea{width:100%;padding:.4em;margin-top:.2em;border:1px solid #ccc;border-radius:4px}
        \\        button{padding:.5em 1em;cursor:pointer;border:1px solid #0366d6;background:#0366d6;color:#fff;border-radius:4px}
        \\    </style>
        \\</head>
        \\<body>
        \\    <nav>
        \\        <a href="/">Home</a>
        \\        <a href="/post/new">New Post</a>
        \\        {% if authenticated %}
        \\            <form method="post" action="/logout">
        \\                <input type="hidden" name="_csrf" value="zypher-csrf-secret-key-2026">
        \\                <button type="submit">Logout ({{ username }})</button>
        \\            </form>
        \\        {% else %}
        \\            <a href="/login">Login</a>
        \\            <a href="/register">Register</a>
        \\        {% endif %}
        \\    </nav>
        \\    {% if flash %}
        \\        <div class="flash {{ flash_type|safe }}">{{ flash }}</div>
        \\    {% endif %}
        \\    {{ content|safe }}
        \\</body>
        \\</html>
    );
    Site.loadTemplates(&engine);
    tlengine = &engine;
    zypher.admin.setEngine(&engine);

    // ── Session Store ───────────────────────────────────────────────────
    var store = SessionStore.init(allocator);
    defer store.deinit();
    tlstore = &store;
    zypher.middleware.session.setStore(&store);
    zypher.middleware.session.setCookieConfig(.{
        .httponly = true,
        .secure = false,
        .samesite = "Strict",
        .path = "/",
        .max_age = 86400,
    });

    // ── Router ──────────────────────────────────────────────────────────
    const admin_routes = Site.routes();
    const demo_routes = [_]Route{
        Router.route(.get, "/", indexHandler),
        Router.route(.get, "/post/new", newPostFormHandler),
        Router.route(.post, "/post/new", createPostHandler),
        Router.route(.get, "/post/:id", postDetailHandler),
        Router.route(.post, "/post/:id/comment", addCommentHandler),
        Router.route(.get, "/register", registerFormHandler),
        Router.route(.post, "/register", registerHandler),
        Router.route(.get, "/login", loginFormHandler),
        Router.route(.post, "/login", loginHandler),
        Router.route(.post, "/logout", logoutHandler),
    };
    const routes = demo_routes ++ admin_routes;
    var router = Router.initFromSlice(&routes, notFoundHandler);

    // ── Middleware chain ────────────────────────────────────────────────
    tlrouter = &router;

    // ── App ─────────────────────────────────────────────────────────────
    var app = zypher.core.App.init(allocator, .{ .port = 8080 });
    defer app.deinit();
    app.database(&db);
    app.middlewareHandler(mwHandler);
    zypher.admin.setDb(&db);

    try app.listenAndServe(io);
}
