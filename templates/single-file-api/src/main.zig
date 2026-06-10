const std = @import("std");
const zypher = @import("zypher");

const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Route = zypher.router.Route;
const Router = zypher.router.Router;
const Session = zypher.auth.session.Session;
const SessionStore = zypher.auth.session.SessionStore;
const TemplateEngine = zypher.template.renderer.TemplateEngine;
const sqlite = zypher.orm.sqlite;
const schema = zypher.orm.schema;
const password = zypher.auth.password;
const AdminSite = zypher.admin.AdminSite;
const Registration = zypher.admin.Registration;

const ManagedItemFields = struct {
    id: schema.FieldDef = schema.Field("id", .integer, .{ .primary = true }),
    name: schema.FieldDef = schema.Field("name", .text, .{ .required = true }),
    description: schema.FieldDef = schema.Field("description", .text, .{}),
};
const ManagedItem = schema.Model("managed_items", ManagedItemFields);
const Admin = AdminSite(.{ .managed_items = Registration(ManagedItem, .{ .verbose_name_plural = "Managed Items" }) });
const Chain = zypher.middleware.Chain(.{ zypher.middleware.session.middleware, zypher.middleware.security_headers.middleware });

threadlocal var tl_db: ?*sqlite.Db = null;
threadlocal var tl_router: ?*const Router = null;

fn index(_: *Request, res: *Response) void {
    res.json(.{ .app = "{{project_name}}", .style = "single-file-api", .ok = true }) catch {};
}

fn adminLoginInfo(_: *Request, res: *Response) void {
    res.json(.{ .login = "/admin/login", .method = "POST", .fields = "username,password" }) catch {};
}

fn adminLogin(req: *Request, res: *Response) void {
    const username = req.formValue("username") orelse "";
    const plain = req.formValue("password") orelse "";
    const db = tl_db orelse return;
    var stmt = db.prepare("SELECT password_hash, role, is_active FROM users WHERE username = ?") catch return unauthorized(res);
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
    try db.exec(ManagedItem.create_table_sql);
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
        Router.route(.get, "/", index),
        Router.route(.get, "/admin", adminEntry),
        Router.route(.get, "/admin/login", adminLoginInfo),
        Router.route(.post, "/admin/login", adminLogin),
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

test "api app imports zypher" {
    try std.testing.expect(@hasDecl(zypher, "core"));
}
