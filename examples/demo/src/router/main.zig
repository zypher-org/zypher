const std = @import("std");
const zypher = @import("zypher");
const Handler = zypher.router.Handler;
const handler = zypher.router.handler;
const controller = @import("controller");

const RouteTable = std.static_string_map.StaticStringMap(Handler).init(.{
    .{ "/", handler(controller.getTodos, &.{}, .get) },
    .{ "/", handler(controller.createTodo, &.{}, .post) },
    .{ "/{id}", handler(controller.getTodo, &.{ .id = controller.id }, .get) },
    .{ "/{id}", handler(controller.deleteTodo, &.{ .id = controller.id }, .delete) },
    .{ "/{id}", handler(controller.updateTodo, &.{ .id = controller.id }, .put) },
}, zypher.gpa);
