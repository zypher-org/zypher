const zypher = @import("zypher");
const service = @import("../application/resource_service.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;

pub fn index(_: *Request, res: *Response) void {
    res.json(.{ .data = service.listResources() }) catch {};
}
