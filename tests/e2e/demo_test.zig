const std = @import("std");
const demo = @import("demo");
const zypher = @import("zypher");
const SqliteDb = zypher.orm.driver.sqlite.SqliteDb;
const RelationalDb = zypher.orm.driver.interface.RelationalDb;
const sqlite = zypher.orm.sqlite;
const query = zypher.orm.query;
const password = zypher.auth.password;

fn hasMiddleware(name: []const u8) bool {
    for (demo.middleware_names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

test "demo app exposes Phase 10 feature contract" {
    try std.testing.expectEqualStrings("posts", demo.Post.table_name);
    try std.testing.expectEqualStrings("comments", demo.Comment.table_name);

    try std.testing.expect(demo.FeatureContract.hasPostModel);
    try std.testing.expect(demo.FeatureContract.hasCommentModel);
    try std.testing.expect(demo.FeatureContract.hasRegisterLoginLogout);
    try std.testing.expect(demo.FeatureContract.hasAdminPostAndComment);
    try std.testing.expect(demo.FeatureContract.hasPostAndCommentViews);
    try std.testing.expect(demo.FeatureContract.hasPostAndCommentForms);

    try std.testing.expect(hasMiddleware("logger"));
    try std.testing.expect(hasMiddleware("csrf"));
    try std.testing.expect(hasMiddleware("rate-limit"));
}

test "demo forms validate required post and comment input" {
    var empty_post = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer empty_post.deinit();
    var bound_post = try demo.PostForm.bind(std.testing.allocator, &empty_post);
    defer bound_post.deinit();
    try std.testing.expect(!bound_post.validate());
    try std.testing.expect(bound_post.errors.contains("title"));
    try std.testing.expect(bound_post.errors.contains("body"));

    var valid_post = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer valid_post.deinit();
    try valid_post.put("title", "Hello");
    try valid_post.put("body", "A demo post");
    var valid_bound_post = try demo.PostForm.bind(std.testing.allocator, &valid_post);
    defer valid_bound_post.deinit();
    try std.testing.expect(valid_bound_post.validate());

    var empty_comment = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer empty_comment.deinit();
    var bound_comment = try demo.CommentForm.bind(std.testing.allocator, &empty_comment);
    defer bound_comment.deinit();
    try std.testing.expect(!bound_comment.validate());
    try std.testing.expect(bound_comment.errors.contains("body"));
}

test "register user via ORM: create user, hash password, authenticate" {
    var sdb = try SqliteDb.open(std.testing.allocator, ":memory:");
    defer sdb.close();

    try sdb.exec(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  username TEXT NOT NULL UNIQUE,
        \\  password_hash TEXT NOT NULL,
        \\  role TEXT NOT NULL DEFAULT 'user',
        \\  is_active INTEGER NOT NULL DEFAULT 1
        \\)
    );

    const hash = try password.hash(std.testing.io, std.testing.allocator, "secure_password");
    defer std.testing.allocator.free(hash);

    const insert_sql = "INSERT INTO users (username, password_hash, role, is_active) VALUES (?, ?, 'user', 1)";
    var stmt = try sdb.prepare(insert_sql);
    defer stmt.finalize();
    try stmt.bind(.{ .text = "testuser" }, 1);
    try stmt.bind(.{ .text = hash }, 2);
    _ = try stmt.step();

    var lookup = try sdb.prepare("SELECT password_hash, role FROM users WHERE username = ?");
    defer lookup.finalize();
    try lookup.bind(.{ .text = "testuser" }, 1);
    try std.testing.expect(try lookup.step());

    const stored_hash = (try lookup.column(.text, 0)).text;
    const role = (try lookup.column(.text, 1)).text;
    try std.testing.expectEqualStrings("user", role);
    try std.testing.expect(try password.verify(stored_hash, "secure_password"));
    try std.testing.expect(!try password.verify(stored_hash, "wrong_password"));
}

test "create post and comment, verify data flow end-to-end" {
    var sdb = try SqliteDb.open(std.testing.allocator, ":memory:");
    defer sdb.close();
    const db = sdb.asRelationalDb();

    try sdb.exec(demo.Post.create_table_sql);
    try sdb.exec(demo.Comment.create_table_sql);

    const gpa = std.testing.allocator;

    const post_id = try query.create(demo.Post, db, &.{
        sqlite.Value{ .text = "Test Post" },
        sqlite.Value{ .text = "This is the body of the test post." },
        sqlite.Value{ .text = "alice" },
        sqlite.Value{ .int = 1000000 },
    });

    var posts = try query.all(demo.Post, db, gpa);
    defer {
        for (posts.items) |*r| query.freeRow(demo.Post, gpa, r);
        posts.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 1), posts.items.len);
    try std.testing.expectEqualStrings("Test Post", posts.items[0][1]);

    _ = try query.create(demo.Comment, db, &.{
        sqlite.Value{ .int = post_id },
        sqlite.Value{ .text = "bob" },
        sqlite.Value{ .text = "Great post!" },
        sqlite.Value{ .int = 1000001 },
    });

    var comments = try query.filter(demo.Comment, db, gpa, "post_id = ?", &.{.{ .int = post_id }});
    defer {
        for (comments.items) |*r| query.freeRow(demo.Comment, gpa, r);
        comments.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 1), comments.items.len);
    try std.testing.expectEqualStrings("bob", comments.items[0][2]);
    try std.testing.expectEqualStrings("Great post!", comments.items[0][3]);

    var all_comments = try query.all(demo.Comment, db, gpa);
    defer {
        for (all_comments.items) |*r| query.freeRow(demo.Comment, gpa, r);
        all_comments.deinit(gpa);
    }
    try std.testing.expectEqual(@as(usize, 1), all_comments.items.len);
}

test "admin site exposes routes for registered models" {
    const routes = demo.Site.routes();
    try std.testing.expect(routes.len >= 14);

    var has_admin_index = false;
    var has_posts_list = false;
    var has_comments_list = false;
    for (routes) |r| {
        if (std.mem.eql(u8, r.pattern, "/admin/")) has_admin_index = true;
        if (std.mem.eql(u8, r.pattern, "/admin/posts/")) has_posts_list = true;
        if (std.mem.eql(u8, r.pattern, "/admin/comments/")) has_comments_list = true;
    }
    try std.testing.expect(has_admin_index);
    try std.testing.expect(has_posts_list);
    try std.testing.expect(has_comments_list);
}

test "logout: session destruction works via session store" {
    var store = zypher.auth.session.SessionStore.init(std.testing.allocator);
    defer store.deinit();

    var session = store.create(std.testing.io);
    defer session.deinit(std.testing.allocator);
    try session.put(std.testing.allocator, "username", "testuser");
    try store.save(&session);

    const retrieved = try store.get(session.id, std.testing.io);
    try std.testing.expect(retrieved != null);

    try store.destroy(session.id);
    const after_destroy = try store.get(session.id, std.testing.io);
    try std.testing.expect(after_destroy == null);
}
