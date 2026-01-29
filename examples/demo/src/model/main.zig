const Todo = struct {
    id: usize,
    title: []const u8,
    description: []const u8,
    priority: Priority,

    const Priority = enum { low, moderate, high, critical };
};
