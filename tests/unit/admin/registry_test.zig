/// Tests for admin registry — model registration, route generation.
const std = @import("std");
const zypher = @import("zypher");
const schema = zypher.orm.schema;
const admin = zypher.admin;

const Field = schema.Field;
const FieldDef = schema.FieldDef;
const Model = schema.Model;

// ── Test models ─────────────────────────────────────────────────────────────

const BookFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    title: FieldDef = Field("title", .text, .{ .required = true }),
    author: FieldDef = Field("author", .text, .{}),
    year: FieldDef = Field("year", .integer, .{}),
};
const Book = Model("books", BookFields);

const CategoryFields = struct {
    id: FieldDef = Field("id", .integer, .{ .primary = true }),
    name: FieldDef = Field("name", .text, .{ .required = true }),
};
const Category = Model("categories", CategoryFields);

// ── Admin site with two registered models ───────────────────────────────────

const Site = admin.AdminSite(.{
    .books = admin.Registration(Book, .{ .list_display = &.{ "title", "author", "year" }, .list_per_page = 10 }),
    .categories = admin.Registration(Category, .{ .verbose_name_plural = "Categories" }),
});

test "admin registration: routes generated for registered models" {
    const routes = comptime Site.routes();
    // 2 models × 7 routes each + 1 index = 15
    try std.testing.expectEqual(@as(usize, 15), routes.len);
}

test "admin registration: index route is first" {
    const routes = comptime Site.routes();
    try std.testing.expectEqualStrings("/admin/", routes[0].pattern);
}

test "admin registration: model list routes exist" {
    const routes = comptime Site.routes();
    var found_books_list = false;
    var found_categories_list = false;
    for (routes) |r| {
        if (std.mem.eql(u8, r.pattern, "/admin/books/")) found_books_list = true;
        if (std.mem.eql(u8, r.pattern, "/admin/categories/")) found_categories_list = true;
    }
    try std.testing.expect(found_books_list);
    try std.testing.expect(found_categories_list);
}

test "admin registration: model add/create routes exist" {
    const routes = comptime Site.routes();
    var found_add = false;
    var found_create = false;
    for (routes) |r| {
        if (std.mem.eql(u8, r.pattern, "/admin/books/add/") and r.method == .get) found_add = true;
        if (std.mem.eql(u8, r.pattern, "/admin/books/add/") and r.method == .post) found_create = true;
    }
    try std.testing.expect(found_add);
    try std.testing.expect(found_create);
}

test "admin registration: model edit and delete routes exist" {
    const routes = comptime Site.routes();
    var found_edit = false;
    var found_update = false;
    var found_delete_get = false;
    var found_delete_post = false;
    for (routes) |r| {
        if (std.mem.eql(u8, r.pattern, "/admin/books/:id/change/") and r.method == .get) found_edit = true;
        if (std.mem.eql(u8, r.pattern, "/admin/books/:id/change/") and r.method == .post) found_update = true;
        if (std.mem.eql(u8, r.pattern, "/admin/books/:id/delete/") and r.method == .get) found_delete_get = true;
        if (std.mem.eql(u8, r.pattern, "/admin/books/:id/delete/") and r.method == .post) found_delete_post = true;
    }
    try std.testing.expect(found_edit);
    try std.testing.expect(found_update);
    try std.testing.expect(found_delete_get);
    try std.testing.expect(found_delete_post);
}

test "admin registration: empty admin site" {
    const Empty = admin.AdminSite(.{});
    const routes = comptime Empty.routes();
    try std.testing.expectEqual(@as(usize, 1), routes.len);
    try std.testing.expectEqualStrings("/admin/", routes[0].pattern);
}

test "admin registration: model metadata accessible" {
    const info = comptime Site.modelInfo("books");
    try std.testing.expectEqualStrings("books", info.table_name);
    try std.testing.expect(info.field_count > 0);
}
