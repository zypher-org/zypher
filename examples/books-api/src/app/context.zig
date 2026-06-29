const zypher = @import("zypher");

const Router = zypher.router.Router;
const RelationalDb = zypher.orm.query.RelationalDb;

threadlocal var db_val: ?RelationalDb = null;
threadlocal var router_ptr: ?*const Router = null;

pub fn set(database: RelationalDb, app_router: *const Router) void {
    db_val = database;
    router_ptr = app_router;
}

pub fn db() RelationalDb {
    return db_val orelse @panic("books-api: database not initialized");
}

pub fn router() *const Router {
    return router_ptr orelse @panic("books-api: router not initialized");
}
