const std = @import("std");
const zypher = @import("zypher");

const context = @import("app/context.zig");
const book = @import("models/book.zig");
const books = @import("controllers/book_controller.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Route = zypher.router.Route;
const Router = zypher.router.Router;
const Session = zypher.auth.session.Session;
const SessionStore = zypher.auth.session.SessionStore;
const TemplateEngine = zypher.template.renderer.TemplateEngine;
const sqlite = zypher.orm.sqlite;
const RelationalDb = zypher.orm.query.RelationalDb;
const password = zypher.auth.password;
const AdminSite = zypher.admin.AdminSite;
const Registration = zypher.admin.Registration;

const Admin = AdminSite(.{
    .books = Registration(book.Book, .{ .verbose_name_plural = "Books" }),
});

const Chain = zypher.middleware.Chain(.{
    zypher.middleware.session.middleware,
    zypher.middleware.security_headers.middleware,
});

fn index(_: *Request, res: *Response) void {
    res.json(.{
        .name = "books-api",
        .routes = .{
            .list = "GET /api/books",
            .create = "POST /api/books",
            .show = "GET /api/books/:id",
            .update = "POST /api/books/:id",
            .delete = "POST /api/books/:id/delete",
        },
    }) catch {};
}

fn loginInfo(_: *Request, res: *Response) void {
    res.json(.{ .login = "/admin/login", .method = "POST", .fields = "username,password", .forgot_password = "/admin/forgot-password", .reset_password = "/admin/reset-password" }) catch {};
}

fn login(req: *Request, res: *Response) void {
    const username = req.formValue("username") orelse "";
    const plain = req.formValue("password") orelse "";
    var stmt = context.db().prepare("SELECT password_hash, role, is_active FROM users WHERE username = ?") catch return unauthorized(res);
    defer stmt.finalize();
    stmt.bind(.{ .text = username }, 1) catch return;
    if (!(stmt.step() catch false)) return unauthorized(res);
    const hash = stmt.column(.text, 0) catch return;
    const role = stmt.column(.text, 1) catch return;
    const active = stmt.column(.integer, 2) catch return;
    if (active.int != 1 or !std.mem.eql(u8, role.text, "admin") or !(password.verify(hash.text, plain) catch false)) return unauthorized(res);
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        session.put(req.allocator, "username", username) catch {};
        session.put(req.allocator, "role", "admin") catch {};
    }
    res.json(.{ .ok = true, .redirect = "/admin/" }) catch {};
}

fn ensureAuthRecoverySchema(db: RelationalDb) void {
    if (!userColumnExists(db, "email")) db.exec("ALTER TABLE users ADD COLUMN email TEXT") catch {};
    if (!userColumnExists(db, "reset_code")) db.exec("ALTER TABLE users ADD COLUMN reset_code TEXT") catch {};
    if (!userColumnExists(db, "reset_code_expires_at")) db.exec("ALTER TABLE users ADD COLUMN reset_code_expires_at INTEGER") catch {};
}

fn userColumnExists(db: RelationalDb, name: []const u8) bool {
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

fn unixTimestamp() i64 {
    return std.Io.Timestamp.now(tl_io, .real).toSeconds();
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

fn forgotPasswordInfo(_: *Request, res: *Response) void {
    res.json(.{ .forgot_password = "/admin/forgot-password", .method = "POST", .fields = "email" }) catch {};
}

fn forgotPassword(req: *Request, res: *Response) void {
    const email = req.formValue("email") orelse "";
    const db = context.db();
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT username FROM users WHERE email = ? AND role = 'admin' AND is_active = 1") catch return genericRecoveryResponse(res);
    defer stmt.finalize();
    stmt.bind(.{ .text = email }, 1) catch return;
    if (!(stmt.step() catch false)) return genericRecoveryResponse(res);
    const code = generateRecoveryCode(req.allocator) catch return;
    defer req.allocator.free(code);
    var update = db.prepare("UPDATE users SET reset_code = ?, reset_code_expires_at = ? WHERE email = ?") catch return;
    defer update.finalize();
    update.bind(.{ .text = code }, 1) catch return;
    update.bind(.{ .int = unixTimestamp() + 900 }, 2) catch return;
    update.bind(.{ .text = email }, 3) catch return;
    _ = update.step() catch return;
    res.json(.{ .ok = true, .message = "if_account_exists_code_was_sent" }) catch {};
}

fn resetPasswordInfo(_: *Request, res: *Response) void {
    res.json(.{ .reset_password = "/admin/reset-password", .method = "POST", .fields = "email,code,password,confirm_password" }) catch {};
}

fn resetPassword(req: *Request, res: *Response) void {
    const email = req.formValue("email") orelse "";
    const code = req.formValue("code") orelse "";
    const plain = req.formValue("password") orelse "";
    const confirm = req.formValue("confirm_password") orelse "";
    if (!std.mem.eql(u8, plain, confirm) or !passwordStrong(plain)) {
        _ = res.status(400);
        res.json(.{ .message = "weak_or_mismatched_password" }) catch {};
        return;
    }
    const db = context.db();
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT reset_code, reset_code_expires_at FROM users WHERE email = ? AND role = 'admin' AND is_active = 1") catch return invalidRecoveryCode(res);
    defer stmt.finalize();
    stmt.bind(.{ .text = email }, 1) catch return;
    if (!(stmt.step() catch false)) return invalidRecoveryCode(res);
    const stored = stmt.column(.text, 0) catch return invalidRecoveryCode(res);
    const expires = stmt.column(.integer, 1) catch return invalidRecoveryCode(res);
    if (expires.int < unixTimestamp() or !std.mem.eql(u8, stored.text, code)) return invalidRecoveryCode(res);
    const hash = password.hash(tl_io, req.allocator, plain) catch return;
    defer req.allocator.free(hash);
    var update = db.prepare("UPDATE users SET password_hash = ?, reset_code = NULL, reset_code_expires_at = NULL WHERE email = ?") catch return;
    defer update.finalize();
    update.bind(.{ .text = hash }, 1) catch return;
    update.bind(.{ .text = email }, 2) catch return;
    _ = update.step() catch return;
    res.json(.{ .ok = true, .message = "password_reset" }) catch {};
}

fn genericRecoveryResponse(res: *Response) void {
    res.json(.{ .ok = true, .message = "if_account_exists_code_was_sent" }) catch {};
}

fn invalidRecoveryCode(res: *Response) void {
    _ = res.status(400);
    res.json(.{ .message = "invalid_recovery_code" }) catch {};
}

fn unauthorized(res: *Response) void {
    _ = res.status(401);
    res.json(.{ .message = "invalid_credentials" }) catch {};
}

fn adminEntry(_: *Request, res: *Response) void {
    res.redirect("/admin/login", 302) catch {};
}

fn notFound(_: *Request, res: *Response) void {
    _ = res.status(404);
    res.json(.{ .message = "not_found" }) catch {};
}

threadlocal var tl_io: std.Io = undefined;

fn dispatch(req: *Request, res: *Response) void {
    context.router().dispatch(req, res);
}

fn runChain(req: *Request, res: *Response) void {
    Chain.run(tl_io, req, res, dispatch);
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
    var db_conn = try sqlite.Db.open(init.gpa, "books_api.db");
    defer db_conn.close();
    try book.migrate(db_conn.asRelationalDb());

    var engine = TemplateEngine.init(init.gpa);
    defer engine.deinit();
    Admin.loadTemplates(&engine);
    zypher.admin.setDb(db_conn.asRelationalDb());
    zypher.admin.setEngine(&engine);

    var sessions = SessionStore.init(init.gpa);
    defer sessions.deinit();
    zypher.middleware.session.setStore(&sessions);
    zypher.middleware.session.setCookieConfig(.{ .secure = false }); // DEV_ONLY: set to true in production

    const admin_routes = Admin.routes();
    const app_routes = [_]Route{
        Router.route(.get, "/", index),
        Router.route(.get, "/api/books", books.list),
        Router.route(.post, "/api/books", books.create),
        Router.route(.get, "/api/books/:id", books.show),
        Router.route(.post, "/api/books/:id", books.update),
        Router.route(.post, "/api/books/:id/delete", books.delete),
        Router.route(.get, "/admin", adminEntry),
        Router.route(.get, "/admin/login", loginInfo),
        Router.route(.post, "/admin/login", login),
        Router.route(.get, "/admin/forgot-password", forgotPasswordInfo),
        Router.route(.post, "/admin/forgot-password", forgotPassword),
        Router.route(.get, "/admin/reset-password", resetPasswordInfo),
        Router.route(.post, "/admin/reset-password", resetPassword),
    };
    const routes = app_routes ++ admin_routes;
    var router = Router.initFromSlice(&routes, notFound);
    context.set(db_conn.asRelationalDb(), &router);

    tl_io = init.io;
    context.setIo(tl_io);
    var app = zypher.core.App.init(init.gpa, .{ .host = "127.0.0.1", .port = parsePort(init) });
    defer app.deinit();
    app.middlewareHandler(runChain);
    try app.listenAndServe(init.io);
}

test "book schema exposes books table" {
    try std.testing.expectEqualStrings("books", book.Book.table_name);
}
