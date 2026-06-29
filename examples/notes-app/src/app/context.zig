const zypher = @import("zypher");

pub const AppContext = struct {
    db: zypher.orm.query.RelationalDb,
    engine: *zypher.template.renderer.TemplateEngine,
    sessions: *zypher.auth.session.SessionStore,
    router: *const zypher.router.Router,
};

threadlocal var current: ?*AppContext = null;

pub fn set(ctx: *AppContext) void {
    current = ctx;
}

pub fn get() *AppContext {
    return current orelse @panic("notes-app context is not configured");
}
