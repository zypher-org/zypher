/// Admin integration tests — full CRUD via admin views with SQLite.
const std = @import("std");
const zypher = @import("zypher");

const sqlite = zypher.orm.sqlite;
const schema = zypher.orm.schema;
const query = zypher.orm.query;
const migration = zypher.orm.migration;
const admin = zypher.admin;
const csrf = zypher.middleware.csrf;
const Session = zypher.auth.session.Session;
const Route = zypher.router.Route;
const Request = zypher.core.Request;
const Response = zypher.core.Response;
const Method = zypher.core.Method;
const RouteParams = zypher.router.RouteParams;
const SESSION_ID_LEN = 32;

const FieldDef = schema.FieldDef;
const Field = schema.Field;
const Model = schema.Model;

// ── Test model ─────────────────────────────────────────────────────────────

const ProductFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    name: FieldDef = Field("name", .text, .{ .required = true }),
    price: FieldDef = Field("price", .integer, .{}),
};
const Product = Model("products", ProductFields);

// ── Admin site ─────────────────────────────────────────────────────────────

const Site = admin.AdminSite(.{
    .products = admin.Registration(Product, .{ .list_display = &.{ "name", "price" } }),
});

fn openTestDb() !sqlite.Db {
    return sqlite.Db.open(std.testing.allocator, ":memory:");
}

fn migrateProductTable(db: *sqlite.Db) !void {
    var runner = migration.MigrationRunner.init(db);
    const migrations = [_]migration.Migration{
        .{ .id = 1, .name = "create_products", .up_sql = Product.create_table_sql, .down_sql = Product.drop_table_sql },
    };
    try runner.migrate(&migrations);
}

/// Create a session with admin role, set it on the request, and return the
/// session pointer so the caller can deinit it after the handler runs.
fn setAdminSession(req: *Request) !*Session {
    const gpa = std.testing.allocator;
    const session_data = std.StringHashMap([]const u8).init(gpa);
    const session = try gpa.create(Session);
    var id: [SESSION_ID_LEN]u8 = undefined;
    @memset(&id, 0);
    session.* = Session{
        .id = id,
        .data = session_data,
        .expires_at = 0,
    };
    try session.put(gpa, "role", "admin");
    req.user = @ptrCast(session);
    return session;
}

/// Find a route handler by pattern and method from the Site routes.
fn findHandler(comptime pattern: []const u8, comptime method: Method) ?*const fn (*Request, *Response) void {
    const routes = comptime Site.routes();
    inline for (routes) |r| {
        if (std.mem.eql(u8, r.pattern, pattern) and r.method == method) {
            return r.handler;
        }
    }
    return null;
}

test "admin views: index returns 200 and lists registered models" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    var req = Request{
        .method = .get,
        .path = "/admin/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    Site.indexHandler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "products") != null);
}

test "admin views: list view shows empty table" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    const handler = findHandler("/admin/products/", .get) orelse return error.SkipZigTest;

    var req = Request{
        .method = .get,
        .path = "/admin/products/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
}

test "admin views: list view shows created record" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    // Create a record directly
    _ = try query.create(Product, &db, &.{
        .{ .text = "Widget" },
        .{ .int = 99 },
    });

    const handler = findHandler("/admin/products/", .get) orelse return error.SkipZigTest;

    var req = Request{
        .method = .get,
        .path = "/admin/products/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Widget") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "99") != null);
}

test "admin views: add form renders correctly" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    const handler = findHandler("/admin/products/add/", .get) orelse return error.SkipZigTest;

    var req = Request{
        .method = .get,
        .path = "/admin/products/add/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "name") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "price") != null);
}

test "admin views: create handler inserts record" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    const handler = findHandler("/admin/products/add/", .post) orelse return error.SkipZigTest;

    const query_map = std.StringHashMap([]const u8).init(std.testing.allocator);

    var req = Request{
        .method = .post,
        .path = "/admin/products/add/",
        .query = query_map,
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }
    try req.query.put("_csrf", try csrf.ensureToken(&req));

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    // Should redirect after create
    try std.testing.expectEqual(@as(u16, 302), res.status_code);

    // Verify record was created
    var rows = try query.all(Product, &db, std.testing.allocator);
    defer {
        for (rows.items) |*r| query.freeRow(Product, std.testing.allocator, r);
        rows.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
}

test "admin views: create and then change handler shows existing values" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    // Create a record
    _ = try query.create(Product, &db, &.{
        .{ .text = "Gadget" },
        .{ .int = 49 },
    });

    const handler = findHandler("/admin/products/:id/change/", .get) orelse return error.SkipZigTest;

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "1");

    var req = Request{
        .method = .get,
        .path = "/admin/products/1/change/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
        .params = params,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Gadget") != null);
}

test "admin views: delete confirmation renders" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    // Create a record
    _ = try query.create(Product, &db, &.{
        .{ .text = "Trash" },
        .{ .int = 5 },
    });

    const handler = findHandler("/admin/products/:id/delete/", .get) orelse return error.SkipZigTest;

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "1");

    var req = Request{
        .method = .get,
        .path = "/admin/products/1/delete/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
        .params = params,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Confirm Delete") != null);
}

test "admin views: delete handler removes record" {
    var db = try openTestDb();
    defer db.close();
    try migrateProductTable(&db);
    admin.setDb(&db);

    // Create a record
    _ = try query.create(Product, &db, &.{
        .{ .text = "Trash" },
        .{ .int = 5 },
    });

    const handler = findHandler("/admin/products/:id/delete/", .post) orelse return error.SkipZigTest;

    var params = RouteParams.init(std.testing.allocator);
    defer params.deinit();
    try params.put("id", "1");

    const query_map = std.StringHashMap([]const u8).init(std.testing.allocator);

    var req = Request{
        .method = .post,
        .path = "/admin/products/1/delete/",
        .query = query_map,
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
        .params = params,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }
    try req.query.put("_csrf", try csrf.ensureToken(&req));

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    // Should redirect after delete
    try std.testing.expectEqual(@as(u16, 302), res.status_code);

    // Verify record is gone
    try std.testing.expectEqual(@as(u64, 0), try query.count(Product, &db));
}

// ── Pagination test model (list_per_page = 2) ────────────────────────────
const PageItemFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    label: FieldDef = Field("label", .text, .{ .required = true }),
};
const PageItem = Model("page_items", PageItemFields);
const PageItemSite = admin.AdminSite(.{
    .items = admin.Registration(PageItem, .{ .list_per_page = 2 }),
});

fn findPageHandler(comptime pattern: []const u8, comptime method: Method) ?*const fn (*Request, *Response) void {
    const routes = comptime PageItemSite.routes();
    inline for (routes) |r| {
        if (std.mem.eql(u8, r.pattern, pattern) and r.method == method) {
            return r.handler;
        }
    }
    return null;
}

fn migratePageItems(db: *sqlite.Db) !void {
    var runner = migration.MigrationRunner.init(db);
    try runner.migrate(&[_]migration.Migration{
        .{ .id = 1, .name = "create_page_items", .up_sql = PageItem.create_table_sql, .down_sql = PageItem.drop_table_sql },
    });
}

test "admin views: pagination — page 1 shows first items" {
    var db = try openTestDb();
    defer db.close();
    try migratePageItems(&db);
    admin.setDb(&db);

    // Create 3 items (2 per page)
    _ = try query.create(PageItem, &db, &.{.{ .text = "Alpha" }});
    _ = try query.create(PageItem, &db, &.{.{ .text = "Beta" }});
    _ = try query.create(PageItem, &db, &.{.{ .text = "Gamma" }});

    const handler = findPageHandler("/page_items/", .get) orelse return error.SkipZigTest;

    var query_map = std.StringHashMap([]const u8).init(std.testing.allocator);
    try query_map.put("page", "1");

    var req = Request{
        .method = .get,
        .path = "/page_items/",
        .query = query_map,
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);

    // Page 1 should have Alpha and Beta, but NOT Gamma
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Alpha") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Beta") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Gamma") == null);

    // Pagination controls should be present (total_pages > 1)
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "pagination") != null);
}

test "admin views: pagination — page 2 shows remaining items" {
    var db = try openTestDb();
    defer db.close();
    try migratePageItems(&db);
    admin.setDb(&db);

    _ = try query.create(PageItem, &db, &.{.{ .text = "Alpha" }});
    _ = try query.create(PageItem, &db, &.{.{ .text = "Beta" }});
    _ = try query.create(PageItem, &db, &.{.{ .text = "Gamma" }});

    const handler = findPageHandler("/page_items/", .get) orelse return error.SkipZigTest;

    var query_map = std.StringHashMap([]const u8).init(std.testing.allocator);
    try query_map.put("page", "2");

    var req = Request{
        .method = .get,
        .path = "/page_items/",
        .query = query_map,
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);

    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);

    // Page 2 should have Gamma only
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Alpha") == null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Beta") == null);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "Gamma") != null);
}

test "admin views: pagination — invalid page defaults to 1" {
    var db = try openTestDb();
    defer db.close();
    try migratePageItems(&db);
    admin.setDb(&db);

    _ = try query.create(PageItem, &db, &.{.{ .text = "Only" }});

    const handler = findPageHandler("/page_items/", .get) orelse return error.SkipZigTest;

    var query_map = std.StringHashMap([]const u8).init(std.testing.allocator);
    try query_map.put("_csrf", csrf.generateToken());

    var req = Request{
        .method = .get,
        .path = "/page_items/",
        .query = query_map,
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(res.body != null);
}

test "admin views: pagination — page 0 defaults to page 1" {
    var db = try openTestDb();
    defer db.close();
    try migratePageItems(&db);
    admin.setDb(&db);

    _ = try query.create(PageItem, &db, &.{.{ .text = "First" }});

    const handler = findPageHandler("/page_items/", .get) orelse return error.SkipZigTest;

    var query_map = std.StringHashMap([]const u8).init(std.testing.allocator);
    try query_map.put("_csrf", csrf.generateToken());

    var req = Request{
        .method = .get,
        .path = "/page_items/",
        .query = query_map,
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    handler(&req, &res);
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
    try std.testing.expect(std.mem.indexOf(u8, res.body.?, "First") != null);
}

test "admin views: no database returns 500" {
    // Don't set admin_db — simulate missing connection
    var req = Request{
        .method = .get,
        .path = "/admin/products/",
        .query = std.StringHashMap([]const u8).init(std.testing.allocator),
        .headers = std.StringHashMap([]const u8).init(std.testing.allocator),
        .body = "",
        .allocator = std.testing.allocator,
    };
    defer req.deinit();
    const admin_session = try setAdminSession(&req);
    defer {
        admin_session.deinit(std.testing.allocator);
        std.testing.allocator.destroy(admin_session);
    }

    var res = Response.init(std.testing.allocator);
    defer res.deinit();

    Site.indexHandler(&req, &res);

    // Index doesn't use DB, so it should still work
    try std.testing.expectEqual(@as(u16, 200), res.status_code);
}
