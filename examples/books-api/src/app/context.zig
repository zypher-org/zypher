const zypher = @import("zypher");

const sqlite = zypher.orm.sqlite;
const Router = zypher.router.Router;

threadlocal var db_ptr: ?*sqlite.Db = null;
threadlocal var router_ptr: ?*const Router = null;

pub fn set(database: *sqlite.Db, app_router: *const Router) void {
    db_ptr = database;
    router_ptr = app_router;
}

pub fn db() *sqlite.Db {
    return db_ptr orelse @panic("books-api: database not initialized");
}

pub fn router() *const Router {
    return router_ptr orelse @panic("books-api: router not initialized");
}
