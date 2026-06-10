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
    res.json(.{ .login = "/admin/login", .method = "POST", .fields = "username,password", .forgot_password = "/admin/forgot-password", .reset_password = "/admin/reset-password" }) catch {};
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

fn ensureAuthRecoverySchema(db: *sqlite.Db) void {
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

fn generateRecoveryCode(gpa: std.mem.Allocator, req: *Request) ![]u8 {
    var seed: u64 = @intFromPtr(req);
    seed ^= @intFromPtr(gpa.ptr);
    var prng = std.Random.DefaultPrng.init(seed);
    const n = prng.random().uintLessThan(u32, 1_000_000);
    return std.fmt.allocPrint(gpa, "{d:0>6}", .{n});
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
    const db = tl_db orelse return;
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT username FROM users WHERE email = ? AND role = 'admin' AND is_active = 1") catch return genericRecoveryResponse(res);
    defer stmt.finalize();
    stmt.bind(.{ .text = email }, 1) catch return;
    if (!(stmt.step() catch false)) return genericRecoveryResponse(res);
    const code = generateRecoveryCode(req.allocator, req) catch return;
    defer req.allocator.free(code);
    var update = db.prepare("UPDATE users SET reset_code = ?, reset_code_expires_at = 0 WHERE email = ?") catch return;
    defer update.finalize();
    update.bind(.{ .text = code }, 1) catch return;
    update.bind(.{ .text = email }, 2) catch return;
    _ = update.step() catch return;
    res.json(.{ .ok = true, .message = "recovery_code_sent", .development_code = code }) catch {};
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
    const db = tl_db orelse return;
    ensureAuthRecoverySchema(db);
    var stmt = db.prepare("SELECT reset_code FROM users WHERE email = ? AND role = 'admin' AND is_active = 1") catch return invalidRecoveryCode(res);
    defer stmt.finalize();
    stmt.bind(.{ .text = email }, 1) catch return;
    if (!(stmt.step() catch false)) return invalidRecoveryCode(res);
    const stored = stmt.column(.text, 0) catch return invalidRecoveryCode(res);
    if (!std.mem.eql(u8, stored.text, code)) return invalidRecoveryCode(res);
    const hash = password.hash(req.allocator, plain) catch return;
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
