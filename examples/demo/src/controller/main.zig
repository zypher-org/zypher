const zypher = @import("zypher");

pub fn getTodos(req: *zypher.Request, res: *zypher.Response) !void {
    _ = req;
    try res.text("Hello from zypher 👋");
}
