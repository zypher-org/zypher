const zypher = @import("zypher");

pub fn getTodos(req: *zypher.Request, res: *zypher.Response) !void {
    _ = req;
    try res.json();
}

pub fn getTodo(req: *zypher.Request, res: *zypher.Response) !void {
    _ = req;
    try res.json();
}

pub fn createTodo(req: *zypher.Request, res: *zypher.Response) !void {
    _ = req;
    try res.json();
}

pub fn deleteTodo(req: *zypher.Request, res: *zypher.Response) !void {
    _ = req;
    try res.json();
}
