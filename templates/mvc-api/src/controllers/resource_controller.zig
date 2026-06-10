const zypher = @import("zypher");
const view = @import("../views/resource_view.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;

pub fn index(_: *Request, res: *Response) void {
    res.json(view.listResponse()) catch {};
}
