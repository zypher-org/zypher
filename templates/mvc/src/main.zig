const std = @import("std");
const zypher = @import("zypher");
const model = @import("models/page.zig");
const page_controller = @import("controllers/page_controller.zig");

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
    .managed_items = Registration(model.ManagedItem, .{ .verbose_name_plural = "Managed Items" }),
});

const Chain = zypher.middleware.Chain(.{
    zypher.middleware.session.middleware,
    zypher.middleware.security_headers.middleware,
});

threadlocal var tl_db: ?*sqlite.Db = null;
threadlocal var tl_router: ?*const Router = null;

fn loginForm(_: *Request, res: *Response) void {
    res.html(
        \\<h1>Admin Login</h1>
        \\<form method="post" action="/admin/login">
        \\  <label>Email <input type="email" name="username"></label>
        \\  <label>Password <input type="password" name="password"></label>
        \\  <button type="submit">Log In</button>
        \\</form>
    ) catch {};
}

fn login(req: *Request, res: *Response) void {
    const username = req.formValue("username") orelse "";
    const plain = req.formValue("password") orelse "";
    const db = tl_db orelse return;
    var stmt = db.prepare("SELECT password_hash, role, is_active FROM users WHERE username = ?") catch {
        _ = res.status(401);
        res.text("Invalid credentials") catch {};
        return;
    };
    defer stmt.finalize();
    stmt.bind(.{ .text = username }, 1) catch return;
    if (!(stmt.step() catch false)) {
        _ = res.status(401);
        res.text("Invalid credentials") catch {};
        return;
    }
    const hash = stmt.column(.text, 0) catch return;
    const role = stmt.column(.text, 1) catch return;
    const active = stmt.column(.integer, 2) catch return;
    if (active.int != 1 or !std.mem.eql(u8, role.text, "admin") or !(password.verify(hash.text, plain) catch false)) {
        _ = res.status(401);
        res.text("Invalid credentials") catch {};
        return;
    }
    if (req.user) |user_ptr| {
        const session: *Session = @ptrCast(@alignCast(user_ptr));
        session.put(req.allocator, "username", username) catch {};
        session.put(req.allocator, "role", "admin") catch {};
    }
    res.redirect("/admin/", 302) catch {};
}

fn adminEntry(_: *Request, res: *Response) void {
    res.redirect("/admin/login", 302) catch {};
}

fn notFound(_: *Request, res: *Response) void {
    _ = res.status(404);
    res.text("Not Found") catch {};
}

fn dispatch(req: *Request, res: *Response) void {
    (tl_router orelse return).dispatch(req, res);
}

fn runChain(req: *Request, res: *Response) void {
    Chain.run(req, res, dispatch);
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
    var db = try sqlite.Db.open(init.gpa, "{{project_name}}.db");
    defer db.close();
    try db.exec(model.ManagedItem.create_table_sql);

    var engine = TemplateEngine.init(init.gpa);
    defer engine.deinit();
    Admin.loadTemplates(&engine);
    zypher.admin.setDb(&db);
    zypher.admin.setEngine(&engine);

    var sessions = SessionStore.init(init.gpa);
    defer sessions.deinit();
    zypher.middleware.session.setStore(&sessions);
    zypher.middleware.session.setCookieConfig(.{ .secure = false });

    const admin_routes = Admin.routes();
    const app_routes = [_]Route{
        Router.route(.get, "/", page_controller.home),
        Router.route(.get, "/admin", adminEntry),
        Router.route(.get, "/admin/login", loginForm),
        Router.route(.post, "/admin/login", login),
    };
    const routes = app_routes ++ admin_routes;
    var router = Router.initFromSlice(&routes, notFound);
    tl_db = &db;
    tl_router = &router;

    var app = zypher.core.App.init(init.gpa, .{ .host = "127.0.0.1", .port = parsePort(init) });
    defer app.deinit();
    app.middlewareHandler(runChain);
    try app.listenAndServe(init.io);
}

test "mvc model has title" {
    const page_model = @import("models/page.zig");
    try std.testing.expect(page_model.home().title.len > 0);
}
