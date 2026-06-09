const std = @import("std");
const demo = @import("demo");

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
