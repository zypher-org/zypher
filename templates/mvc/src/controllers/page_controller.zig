const zypher = @import("zypher");
const page_model = @import("../models/page.zig");
const page_view = @import("../views/page_view.zig");

const Request = zypher.core.Request;
const Response = zypher.core.Response;

pub fn home(_: *Request, res: *Response) void {
    const html = page_view.renderHome(res.allocator, page_model.home()) catch {
        _ = res.status(500);
        return;
    };
    defer res.allocator.free(html);
    res.html(html) catch {};
}
