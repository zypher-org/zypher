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
    res.json(.{ .login = "/admin/login", .method = "POST", .fields = "username,password" }) catch {};
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

fn dispatch(req: *Request, res: *Response) void {
    context.router().dispatch(req, res);
}

fn runChain(req: *Request, res: *Response) void {
    Chain.run(req, res, dispatch);
}

pub fn main(init: std.process.Init) !void {
    var db_conn = try sqlite.Db.open(init.gpa, "books_api.db");
    defer db_conn.close();
    try book.migrate(&db_conn);

    var engine = TemplateEngine.init(init.gpa);
    defer engine.deinit();
    Admin.loadTemplates(&engine);
    zypher.admin.setDb(&db_conn);
    zypher.admin.setEngine(&engine);

    var sessions = SessionStore.init(init.gpa);
    defer sessions.deinit();
    zypher.middleware.session.setStore(&sessions);
    zypher.middleware.session.setCookieConfig(.{ .secure = false });

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
    };
    const routes = app_routes ++ admin_routes;
    var router = Router.initFromSlice(&routes, notFound);
    context.set(&db_conn, &router);

    var app = zypher.core.App.init(init.gpa, .{ .host = "127.0.0.1", .port = 8091 });
    defer app.deinit();
    app.middlewareHandler(runChain);
    try app.listenAndServe(init.io);
}

test "book schema exposes books table" {
    try std.testing.expectEqualStrings("books", book.Book.table_name);
}
