const zypher = @import("zypher");
const service = @import("../application/home_service.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;

pub fn index(_: *Request, res: *Response) void {
    const greeting = service.homeGreeting();
    const body = @import("std").fmt.allocPrint(res.allocator, "<h1>{s}</h1><p>{s}</p>", .{ greeting.title, greeting.message }) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(body);
    res.html(body) catch {};
}
