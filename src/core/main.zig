const std = @import("std");

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    HEAD,
};

pub const HeaderMap = std.StringHashMap([]const u8);
