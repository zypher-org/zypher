/// HTTP method enum.
pub const Method = enum {
    get,
    post,
    put,
    patch,
    delete,
    options,
    head,

    /// Convert from std.http.Method to zypher Method.
    pub fn fromStdString(m: std.http.Method) Method {
        return switch (m) {
            .GET => .get,
            .POST => .post,
            .PUT => .put,
            .PATCH => .patch,
            .DELETE => .delete,
            .OPTIONS => .options,
            .HEAD => .head,
            else => .get,
        };
    }

    /// Convert to std.http.Method.
    pub fn toStdString(m: Method) std.http.Method {
        return switch (m) {
            .get => .GET,
            .post => .POST,
            .put => .PUT,
            .patch => .PATCH,
            .delete => .DELETE,
            .options => .OPTIONS,
            .head => .HEAD,
        };
    }
};

const std = @import("std");
