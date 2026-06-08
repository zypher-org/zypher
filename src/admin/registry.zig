/// zypher admin — auto-generated CRUD interface for registered models.
const std = @import("std");
const Route = @import("../router/route.zig").Route;
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const sqlite = @import("../orm/sqlite.zig");
const query = @import("../orm/query.zig");
const TemplateEngine = @import("../template/renderer.zig").TemplateEngine;
const Context = @import("../template/renderer.zig").Context;
const Value = @import("../template/renderer.zig").Value;
const csrf = @import("../middleware/csrf.zig");
const Session = @import("../auth/session.zig").Session;

// ── Thread-local DB connection (set by the application before admin dispatch) ─

threadlocal var admin_db: ?*sqlite.Db = null;
threadlocal var admin_engine: ?*TemplateEngine = null;

pub fn setDb(db: *sqlite.Db) void {
    admin_db = db;
}

pub fn setEngine(engine: *TemplateEngine) void {
    admin_engine = engine;
}

// ── Configuration ───────────────────────────────────────────────────────────

pub const AdminModelOptions = struct {
    verbose_name_plural: ?[]const u8 = null,
    list_display: []const []const u8 = &.{},
    search_fields: []const []const u8 = &.{},
    list_per_page: usize = 25,
};

/// Registration wrapper: embed a model type + options into a struct field value.
pub fn Registration(comptime M: type, comptime opts: AdminModelOptions) type {
    return struct {
        pub const model = M;
        pub const options = opts;
    };
}

// ── Admin Site ─────────────────────────────────────────────────────────────

pub fn AdminSite(comptime config: anytype) type {
    const fields = comptime std.meta.fieldNames(@TypeOf(config));
    const count = fields.len;

    // ── Compile-time validation ──────────────────────────────────────────
    comptime {
        var seen: [count][]const u8 = undefined;
        for (fields, 0..) |name, i| {
            const reg = @field(config, name);
            const type_name = @typeName(reg.model);
            for (seen[0..i]) |s| {
                if (std.mem.eql(u8, s, type_name))
                    @compileError("AdminSite: duplicate model '" ++ type_name ++ "' (field '" ++ name ++ "')");
            }
            seen[i] = type_name;
        }
    }

    // ── Comptime model metadata table ────────────────────────────────────
    const ModelMeta = struct {
        table_name: []const u8,
        verbose_name_plural: []const u8,
        list_display: []const []const u8,
        search_fields: []const []const u8,
        list_per_page: usize,
        field_count: usize,
    };

    const model_meta: [count]ModelMeta = comptime blk: {
        var metas: [count]ModelMeta = undefined;
        for (fields, 0..) |name, i| {
            const reg = @field(config, name);
            const M = reg.model;
            const opts = reg.options;
            metas[i] = .{
                .table_name = M.table_name,
                .verbose_name_plural = opts.verbose_name_plural orelse M.table_name,
                .list_display = opts.list_display,
                .search_fields = opts.search_fields,
                .list_per_page = opts.list_per_page,
                .field_count = M.fields_len,
            };
        }
        break :blk metas;
    };

    const route_count = if (count == 0) 1 else count * 7 + 1;

    return struct {
        pub const model_names = fields;
        pub const model_count = count;
        pub const meta = model_meta;

        pub fn modelInfo(comptime table: []const u8) ModelMeta {
            inline for (fields, 0..) |name, i| {
                _ = name;
                if (std.mem.eql(u8, model_meta[i].table_name, table)) return model_meta[i];
            }
            @compileError("AdminSite: unknown table '" ++ table ++ "'");
        }

        pub fn loadTemplates(engine: *TemplateEngine) void {
            _ = engine.load("admin/base.html", @embedFile("templates/base.html")) catch {};
            _ = engine.load("admin/index.html", @embedFile("templates/index.html")) catch {};
            _ = engine.load("admin/list.html", @embedFile("templates/list.html")) catch {};
            _ = engine.load("admin/form.html", @embedFile("templates/form.html")) catch {};
            _ = engine.load("admin/confirm_delete.html", @embedFile("templates/confirm_delete.html")) catch {};
        }

        pub fn hasDuplicates() bool {
            comptime {
                var seen: [count][]const u8 = undefined;
                for (fields, 0..) |name, i| {
                    _ = name;
                    const reg = @field(config, fields[i]);
                    const tn = @typeName(reg.model);
                    for (seen[0..i]) |s| if (std.mem.eql(u8, s, tn)) return true;
                    seen[i] = tn;
                }
                return false;
            }
        }

        pub fn routes() [route_count]Route {
            var result: [route_count]Route = undefined;
            result[0] = Route.init(.get, "/admin/", indexHandler);

            if (count > 0) {
                inline for (fields, 0..) |name, i| {
                    _ = name;
                    const reg = @field(config, fields[i]);
                    const M = reg.model;
                    const base = "/admin/" ++ M.table_name;
                    const off = i * 7 + 1;

                    result[off + 0] = Route.init(.get, base ++ "/", listHandler(M, model_meta[i].list_per_page));
                    result[off + 1] = Route.init(.get, base ++ "/add/", addHandler(M));
                    result[off + 2] = Route.init(.post, base ++ "/add/", createHandler(M));
                    result[off + 3] = Route.init(.get, base ++ "/:id/change/", changeHandler(M));
                    result[off + 4] = Route.init(.post, base ++ "/:id/change/", updateHandler(M));
                    result[off + 5] = Route.init(.get, base ++ "/:id/delete/", confirmDeleteHandler(M));
                    result[off + 6] = Route.init(.post, base ++ "/:id/delete/", deleteHandler(M));
                }
            }
            return result;
        }

        pub fn indexHandler(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            const gpa = res.allocator;

            // ── try template rendering ─────────────────────────────────
            if (admin_engine) |engine| {
                var list_html: std.ArrayList(u8) = .empty;
                defer list_html.deinit(gpa);
                list_html.appendSlice(gpa, "<ul>\n") catch return;
                inline for (fields, 0..) |name, idx| {
                    _ = name;
                    const m = model_meta[idx];
                    list_html.appendSlice(gpa, "<li><a href=\"/admin/") catch return;
                    list_html.appendSlice(gpa, m.table_name) catch return;
                    list_html.appendSlice(gpa, "/\">") catch return;
                    list_html.appendSlice(gpa, m.verbose_name_plural) catch return;
                    list_html.appendSlice(gpa, "</a></li>\n") catch return;
                }
                list_html.appendSlice(gpa, "</ul>\n") catch return;

                var ctx = Context.init(gpa);
                defer ctx.deinit();
                ctx.put("index_html", .{ .string = list_html.items }) catch {};
                if (renderTmpl(engine, res, "admin/index.html", &ctx)) return;
            }

            // ── fallback inline HTML ───────────────────────────────────
            var html: std.ArrayList(u8) = .empty;
            defer html.deinit(gpa);

            html.appendSlice(gpa,
                \\<!DOCTYPE html><html><head><title>Admin</title>
                \\<meta name="viewport" content="width=device-width">
                \\<style>*{box-sizing:border-box}
                \\body{font-family:system-ui,sans-serif;max-width:960px;margin:2em auto;padding:0 1em}
                \\h1{border-bottom:2px solid #eee;padding-bottom:.5em}
                \\ul{list-style:none;padding:0}
                \\li{margin:.5em 0}
                \\a{color:#0366d6;text-decoration:none}
                \\a:hover{text-decoration:underline}
                \\</style></head><body><h1>Admin</h1><ul>
            ) catch return;

            inline for (fields, 0..) |name, idx| {
                _ = name;
                const m = model_meta[idx];
                html.appendSlice(gpa, "<li><a href=\"/admin/") catch return;
                html.appendSlice(gpa, m.table_name) catch return;
                html.appendSlice(gpa, "/\">") catch return;
                html.appendSlice(gpa, m.verbose_name_plural) catch return;
                html.appendSlice(gpa, "</a></li>\n") catch return;
            }

            html.appendSlice(gpa, "</ul></body></html>") catch return;
            const owned = html.toOwnedSlice(gpa) catch return;
            res.body = owned;
            _ = res.header("Content-Type", "text/html; charset=utf-8");
        }
    };
}

// ── Template rendering helper ─────────────────────────────────────────────

fn requireAdmin(req: *Request, res: *Response) bool {
    const user_ptr = req.user orelse {
        _ = res.status(302);
        _ = res.header("Location", "/login");
        return false;
    };
    const session: *Session = @ptrCast(@alignCast(user_ptr));
    const role = session.get("role") orelse {
        _ = res.status(403);
        res.text("Forbidden: admin access required") catch {};
        return false;
    };
    if (!std.mem.eql(u8, role, "admin")) {
        _ = res.status(403);
        res.text("Forbidden: admin access required") catch {};
        return false;
    }
    return true;
}

fn validateCsrf(req: *Request) bool {
    const token = req.formValue("_csrf") orelse return false;
    return csrf.validateToken(token);
}

fn renderTmpl(engine: *TemplateEngine, res: *Response, comptime name: []const u8, ctx: *Context) bool {
    const gpa = res.allocator;
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();
    engine.render(name, ctx, &aw.writer) catch return false;
    var buf = aw.toArrayList();
    const owned = buf.toOwnedSlice(gpa) catch return false;
    res.body = owned;
    _ = res.header("Content-Type", "text/html; charset=utf-8");
    return true;
}

// ── Per-model handler factories ────────────────────────────────────────────

fn listHandler(comptime M: type, comptime per_page: usize) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            const db = admin_db orelse {
                _ = res.status(500);
                res.text("Admin: no database") catch {};
                return;
            };
            const gpa = res.allocator;
            // ── pagination ──────────────────────────────────────────────
            const page_str = req.formValue("page") orelse "1";
            const page = std.fmt.parseInt(u64, page_str, 10) catch 1;
            const page_actual = if (page == 0) @as(u64, 1) else page;
            const offset = (page_actual - 1) * per_page;

            var rows = query.filterLimitOffset(M, db, gpa, "", &.{}, per_page, offset) catch {
                _ = res.status(500);
                res.text("Admin: query failed") catch {};
                return;
            };
            defer {
                for (rows.items) |*r| query.freeRow(M, gpa, r);
                rows.deinit(gpa);
            }

            const total = query.count(M, db) catch {
                _ = res.status(500);
                res.text("Admin: count failed") catch {};
                return;
            };
            const total_pages = if (total == 0) @as(u64, 1) else (total + per_page - 1) / per_page;

            // ── build pagination HTML ───────────────────────────────────
            var pag_buf: std.ArrayList(u8) = .empty;
            defer pag_buf.deinit(gpa);
            if (total_pages > 1) {
                pag_buf.appendSlice(gpa, "<div class=\"pagination\">") catch return;
                if (page_actual > 1) {
                    pag_buf.appendSlice(gpa, "<a href=\"/admin/") catch return;
                    pag_buf.appendSlice(gpa, M.table_name) catch return;
                    pag_buf.appendSlice(gpa, "/?page=") catch return;
                    {
                        var buf: [32]u8 = undefined;
                        pag_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{page_actual - 1}) catch "") catch return;
                    }
                    pag_buf.appendSlice(gpa, "\">\u{2190} Prev</a> ") catch return;
                }
                pag_buf.appendSlice(gpa, "<span>Page ") catch return;
                {
                    var buf: [32]u8 = undefined;
                    pag_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{page_actual}) catch "") catch return;
                }
                pag_buf.appendSlice(gpa, " of ") catch return;
                {
                    var buf: [32]u8 = undefined;
                    pag_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{total_pages}) catch "") catch return;
                }
                pag_buf.appendSlice(gpa, "</span> ") catch return;
                if (page_actual < total_pages) {
                    pag_buf.appendSlice(gpa, "<a href=\"/admin/") catch return;
                    pag_buf.appendSlice(gpa, M.table_name) catch return;
                    pag_buf.appendSlice(gpa, "/?page=") catch return;
                    {
                        var buf: [32]u8 = undefined;
                        pag_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{page_actual + 1}) catch "") catch return;
                    }
                    pag_buf.appendSlice(gpa, "\">Next \u{2192}</a>") catch return;
                }
                pag_buf.appendSlice(gpa, "</div>") catch return;
            }
            const pagination_html = pag_buf.items;

            // ── build table rows HTML ───────────────────────────────────
            var rows_buf: std.ArrayList(u8) = .empty;
            defer rows_buf.deinit(gpa);
            for (rows.items) |row| {
                rows_buf.appendSlice(gpa, "<tr>") catch return;
                inline for (0..M.fields_len) |i| {
                    rows_buf.appendSlice(gpa, "<td>") catch return;
                    const FT = @typeInfo(query.RowType(M)).@"struct".field_types[i];
                    if (FT == []const u8) {
                        rows_buf.appendSlice(gpa, row[i]) catch return;
                    } else if (FT == i64) {
                        var buf: [32]u8 = undefined;
                        rows_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                    } else if (FT == bool) {
                        rows_buf.appendSlice(gpa, if (row[i]) "true" else "false") catch return;
                    } else if (FT == f64) {
                        var buf: [32]u8 = undefined;
                        rows_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                    }
                    rows_buf.appendSlice(gpa, "</td>") catch return;
                }
                rows_buf.appendSlice(gpa, "<td>") catch return;
                rows_buf.appendSlice(gpa, "<a href=\"/admin/") catch return;
                rows_buf.appendSlice(gpa, M.table_name) catch return;
                rows_buf.appendSlice(gpa, "/") catch return;
                {
                    var buf: [32]u8 = undefined;
                    rows_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[0]}) catch "") catch return;
                }
                rows_buf.appendSlice(gpa, "/change/\">Edit</a> ") catch return;
                rows_buf.appendSlice(gpa, "<a href=\"/admin/") catch return;
                rows_buf.appendSlice(gpa, M.table_name) catch return;
                rows_buf.appendSlice(gpa, "/") catch return;
                {
                    var buf: [32]u8 = undefined;
                    rows_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[0]}) catch "") catch return;
                }
                rows_buf.appendSlice(gpa, "/delete/\">Delete</a>") catch return;
                rows_buf.appendSlice(gpa, "</td></tr>\n") catch return;
            }

            // ── build header HTML ──────────────────────────────────────
            var headers_buf: std.ArrayList(u8) = .empty;
            defer headers_buf.deinit(gpa);
            inline for (0..M.fields_len) |i| {
                const f = M.fieldAt(i);
                headers_buf.appendSlice(gpa, "<th>") catch return;
                headers_buf.appendSlice(gpa, f.name) catch return;
                headers_buf.appendSlice(gpa, "</th>") catch return;
            }
            headers_buf.appendSlice(gpa, "<th>Actions</th>") catch return;

            // ── try template rendering ─────────────────────────────────
            if (admin_engine) |engine| {
                var ctx = Context.init(gpa);
                defer ctx.deinit();
                ctx.put("table_name", .{ .string = M.table_name }) catch {};
                ctx.put("field_headers", .{ .string = headers_buf.items }) catch {};
                ctx.put("rows_html", .{ .string = rows_buf.items }) catch {};
                ctx.put("pagination_html", .{ .string = pagination_html }) catch {};
                if (renderTmpl(engine, res, "admin/list.html", &ctx)) return;
            }

            // ── fallback inline HTML ───────────────────────────────────
            var html: std.ArrayList(u8) = .empty;
            defer html.deinit(gpa);
            html.appendSlice(gpa, "<!DOCTYPE html><html><head><title>") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</title><meta name=\"viewport\" content=\"width=device-width\"><style>*{box-sizing:border-box}body{font-family:system-ui,sans-serif;max-width:960px;margin:2em auto;padding:0 1em}h1{border-bottom:2px solid #eee;padding-bottom:.5em}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:.5em;border-bottom:1px solid #ddd}th{font-weight:600}.pagination{margin-top:1em;text-align:center}.pagination a,.pagination span{margin:0 .3em}.pagination a{color:#0366d6;text-decoration:none}.pagination a:hover{text-decoration:underline}</style></head><body><h1>") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</h1><a href=\"/admin/") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "/add/\">Add</a><table><thead><tr>") catch return;

            inline for (0..M.fields_len) |i| {
                const f = M.fieldAt(i);
                html.appendSlice(gpa, "<th>") catch return;
                html.appendSlice(gpa, f.name) catch return;
                html.appendSlice(gpa, "</th>") catch return;
            }
            html.appendSlice(gpa, "<th>Actions</th></tr></thead><tbody>") catch return;

            for (rows.items) |row| {
                html.appendSlice(gpa, "<tr>") catch return;
                inline for (0..M.fields_len) |i| {
                    html.appendSlice(gpa, "<td>") catch return;
                    const FT = @typeInfo(query.RowType(M)).@"struct".field_types[i];
                    if (FT == []const u8) {
                        html.appendSlice(gpa, row[i]) catch return;
                    } else if (FT == i64) {
                        var buf: [32]u8 = undefined;
                        html.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                    } else if (FT == bool) {
                        html.appendSlice(gpa, if (row[i]) "true" else "false") catch return;
                    } else if (FT == f64) {
                        var buf: [32]u8 = undefined;
                        html.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                    }
                    html.appendSlice(gpa, "</td>") catch return;
                }
                html.appendSlice(gpa, "<td>") catch return;
                html.appendSlice(gpa, "<a href=\"/admin/") catch return;
                html.appendSlice(gpa, M.table_name) catch return;
                html.appendSlice(gpa, "/") catch return;
                {
                    var buf: [32]u8 = undefined;
                    html.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[0]}) catch "") catch return;
                }
                html.appendSlice(gpa, "/change/\">Edit</a> ") catch return;
                html.appendSlice(gpa, "<a href=\"/admin/") catch return;
                html.appendSlice(gpa, M.table_name) catch return;
                html.appendSlice(gpa, "/") catch return;
                {
                    var buf: [32]u8 = undefined;
                    html.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[0]}) catch "") catch return;
                }
                html.appendSlice(gpa, "/delete/\">Delete</a>") catch return;
                html.appendSlice(gpa, "</td></tr>\n") catch return;
            }

            html.appendSlice(gpa, "</tbody></table>") catch return;
            html.appendSlice(gpa, pagination_html) catch return;
            html.appendSlice(gpa, "</body></html>") catch return;
            const owned = html.toOwnedSlice(gpa) catch return;
            res.body = owned;
            _ = res.header("Content-Type", "text/html; charset=utf-8");
        }
    };
    return H.handle;
}

fn addHandler(comptime M: type) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            const gpa = res.allocator;

            // ── try template rendering ─────────────────────────────────
            if (admin_engine) |engine| {
                var form_buf: std.ArrayList(u8) = .empty;
                defer form_buf.deinit(gpa);
                inline for (0..M.fields_len) |i| {
                    const f = M.fieldAt(i);
                    if (!f.primary) {
                        form_buf.appendSlice(gpa, "<label>") catch return;
                        form_buf.appendSlice(gpa, f.name) catch return;
                        form_buf.appendSlice(gpa, ": <input type=\"text\" name=\"") catch return;
                        form_buf.appendSlice(gpa, f.name) catch return;
                        form_buf.appendSlice(gpa, "\"></label>\n") catch return;
                    }
                }
                form_buf.appendSlice(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"") catch return;
                form_buf.appendSlice(gpa, csrf.generateToken()) catch return;
                form_buf.appendSlice(gpa, "\">") catch return;

                var ctx = Context.init(gpa);
                defer ctx.deinit();
                ctx.put("page_title", .{ .string = "Add " ++ M.table_name }) catch {};
                ctx.put("table_name", .{ .string = M.table_name }) catch {};
                ctx.put("form_fields", .{ .string = form_buf.items }) catch {};
                if (renderTmpl(engine, res, "admin/form.html", &ctx)) return;
            }

            // ── fallback inline HTML ───────────────────────────────────
            var html: std.ArrayList(u8) = .empty;
            defer html.deinit(gpa);
            html.appendSlice(gpa, "<!DOCTYPE html><html><head><title>Add ") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</title><meta name=\"viewport\" content=\"width=device-width\"><style>*{box-sizing:border-box}body{font-family:system-ui,sans-serif;max-width:640px;margin:2em auto;padding:0 1em}label{display:block;margin:.5em 0}input[type=text]{width:100%;padding:.4em}</style></head><body><h1>Add ") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</h1><form method=\"post\">") catch return;

            inline for (0..M.fields_len) |i| {
                const f = M.fieldAt(i);
                if (!f.primary) {
                    html.appendSlice(gpa, "<label>") catch return;
                    html.appendSlice(gpa, f.name) catch return;
                    html.appendSlice(gpa, ": <input type=\"text\" name=\"") catch return;
                    html.appendSlice(gpa, f.name) catch return;
                    html.appendSlice(gpa, "\"></label>") catch return;
                }
            }

            html.appendSlice(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"") catch return;
            html.appendSlice(gpa, csrf.generateToken()) catch return;
            html.appendSlice(gpa, "\">") catch return;
            html.appendSlice(gpa, "<button type=\"submit\" style=\"margin-top:1em;padding:.5em 1em\">Save</button></form></body></html>") catch return;
            const owned = html.toOwnedSlice(gpa) catch return;
            res.body = owned;
            _ = res.header("Content-Type", "text/html; charset=utf-8");
        }
    };
    return H.handle;
}

fn createHandler(comptime M: type) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            if (!validateCsrf(req)) {
                _ = res.status(403);
                res.text("CSRF token missing or invalid") catch {};
                return;
            }
            const db = admin_db orelse {
                _ = res.status(500);
                res.text("Admin: no database") catch {};
                return;
            };
            var values: [M.insert_field_count]sqlite.Value = undefined;
            var idx: usize = 0;
            inline for (0..M.fields_len) |i| {
                const f = M.fieldAt(i);
                if (!f.primary) {
                    const val = req.formValue(f.name) orelse "";
                    values[idx] = switch (f.kind) {
                        .text => sqlite.Value{ .text = val },
                        .integer => sqlite.Value{ .int = std.fmt.parseInt(i64, val, 10) catch 0 },
                        .float => sqlite.Value{ .float = std.fmt.parseFloat(f64, val) catch 0.0 },
                        .boolean => sqlite.Value{ .int = if (val.len > 0 and val[0] == '1') @as(i64, 1) else 0 },
                    };
                    idx += 1;
                }
            }
            _ = query.create(M, db, &values) catch {
                _ = res.status(500);
                res.text("Admin: create failed") catch {};
                return;
            };
            res.redirect("/admin/" ++ M.table_name ++ "/", 302) catch {};
        }
    };
    return H.handle;
}

fn changeHandler(comptime M: type) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            const db = admin_db orelse {
                _ = res.status(500);
                res.text("Admin: no database") catch {};
                return;
            };
            const gpa = res.allocator;
            const id_str = req.params.get("id") orelse {
                _ = res.status(404);
                res.text("Not Found") catch {};
                return;
            };
            const id = std.fmt.parseInt(i64, id_str, 10) catch {
                _ = res.status(404);
                res.text("Invalid ID") catch {};
                return;
            };
            const row = query.getById(M, db, gpa, id) catch {
                _ = res.status(404);
                res.text("Not Found") catch {};
                return;
            };
            defer query.freeRow(M, gpa, @constCast(&row));

            // ── try template rendering ─────────────────────────────────
            if (admin_engine) |engine| {
                var form_buf: std.ArrayList(u8) = .empty;
                defer form_buf.deinit(gpa);
                inline for (0..M.fields_len) |i| {
                    const f = M.fieldAt(i);
                    if (!f.primary) {
                        form_buf.appendSlice(gpa, "<label>") catch return;
                        form_buf.appendSlice(gpa, f.name) catch return;
                        form_buf.appendSlice(gpa, ": <input type=\"text\" name=\"") catch return;
                        form_buf.appendSlice(gpa, f.name) catch return;
                        form_buf.appendSlice(gpa, "\" value=\"") catch return;
                        const FT = @typeInfo(query.RowType(M)).@"struct".field_types[i];
                        if (FT == []const u8) {
                            form_buf.appendSlice(gpa, row[i]) catch return;
                        } else if (FT == i64) {
                            var buf: [32]u8 = undefined;
                            form_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                        } else if (FT == bool) {
                            form_buf.appendSlice(gpa, if (row[i]) "1" else "0") catch return;
                        } else if (FT == f64) {
                            var buf: [32]u8 = undefined;
                            form_buf.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                        }
                        form_buf.appendSlice(gpa, "\"></label>\n") catch return;
                    }
                }
                form_buf.appendSlice(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"") catch return;
                form_buf.appendSlice(gpa, csrf.generateToken()) catch return;
                form_buf.appendSlice(gpa, "\">") catch return;

                var ctx = Context.init(gpa);
                defer ctx.deinit();
                ctx.put("page_title", .{ .string = "Change " ++ M.table_name }) catch {};
                ctx.put("table_name", .{ .string = M.table_name }) catch {};
                ctx.put("form_fields", .{ .string = form_buf.items }) catch {};
                if (renderTmpl(engine, res, "admin/form.html", &ctx)) return;
            }

            // ── fallback inline HTML ───────────────────────────────────
            var html: std.ArrayList(u8) = .empty;
            defer html.deinit(gpa);
            html.appendSlice(gpa, "<!DOCTYPE html><html><head><title>Change ") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</title><meta name=\"viewport\" content=\"width=device-width\"><style>*{box-sizing:border-box}body{font-family:system-ui,sans-serif;max-width:640px;margin:2em auto;padding:0 1em}label{display:block;margin:.5em 0}input[type=text]{width:100%;padding:.4em}</style></head><body><h1>Change ") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</h1><form method=\"post\">") catch return;

            inline for (0..M.fields_len) |i| {
                const f = M.fieldAt(i);
                if (!f.primary) {
                    html.appendSlice(gpa, "<label>") catch return;
                    html.appendSlice(gpa, f.name) catch return;
                    html.appendSlice(gpa, ": <input type=\"text\" name=\"") catch return;
                    html.appendSlice(gpa, f.name) catch return;
                    html.appendSlice(gpa, "\" value=\"") catch return;
                    const FT = @typeInfo(query.RowType(M)).@"struct".field_types[i];
                    if (FT == []const u8) {
                        html.appendSlice(gpa, row[i]) catch return;
                    } else if (FT == i64) {
                        var buf: [32]u8 = undefined;
                        html.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                    } else if (FT == bool) {
                        html.appendSlice(gpa, if (row[i]) "1" else "0") catch return;
                    } else if (FT == f64) {
                        var buf: [32]u8 = undefined;
                        html.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{row[i]}) catch "") catch return;
                    }
                    html.appendSlice(gpa, "\"></label>") catch return;
                }
            }

            html.appendSlice(gpa, "<input type=\"hidden\" name=\"_csrf\" value=\"") catch return;
            html.appendSlice(gpa, csrf.generateToken()) catch return;
            html.appendSlice(gpa, "\">") catch return;
            html.appendSlice(gpa, "<button type=\"submit\" style=\"margin-top:1em;padding:.5em 1em\">Save</button></form></body></html>") catch return;
            const owned = html.toOwnedSlice(gpa) catch return;
            res.body = owned;
            _ = res.header("Content-Type", "text/html; charset=utf-8");
        }
    };
    return H.handle;
}

fn updateHandler(comptime M: type) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            if (!validateCsrf(req)) {
                _ = res.status(403);
                res.text("CSRF token missing or invalid") catch {};
                return;
            }
            const db = admin_db orelse {
                _ = res.status(500);
                res.text("Admin: no database") catch {};
                return;
            };
            const id_str = req.params.get("id") orelse {
                _ = res.status(404);
                res.text("Not Found") catch {};
                return;
            };
            const id = std.fmt.parseInt(i64, id_str, 10) catch {
                _ = res.status(404);
                res.text("Invalid ID") catch {};
                return;
            };
            var values: [M.insert_field_count]sqlite.Value = undefined;
            var idx: usize = 0;
            inline for (0..M.fields_len) |i| {
                const f = M.fieldAt(i);
                if (!f.primary) {
                    const val = req.formValue(f.name) orelse "";
                    values[idx] = switch (f.kind) {
                        .text => sqlite.Value{ .text = val },
                        .integer => sqlite.Value{ .int = std.fmt.parseInt(i64, val, 10) catch 0 },
                        .float => sqlite.Value{ .float = std.fmt.parseFloat(f64, val) catch 0.0 },
                        .boolean => sqlite.Value{ .int = if (val.len > 0 and val[0] == '1') @as(i64, 1) else 0 },
                    };
                    idx += 1;
                }
            }
            _ = query.updateById(M, db, id, &values) catch {
                _ = res.status(500);
                res.text("Admin: update failed") catch {};
                return;
            };
            res.redirect("/admin/" ++ M.table_name ++ "/", 302) catch {};
        }
    };
    return H.handle;
}

fn confirmDeleteHandler(comptime M: type) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            const db = admin_db orelse {
                _ = res.status(500);
                res.text("Admin: no database") catch {};
                return;
            };
            const gpa = res.allocator;
            const id_str = req.params.get("id") orelse {
                _ = res.status(404);
                res.text("Not Found") catch {};
                return;
            };
            const id = std.fmt.parseInt(i64, id_str, 10) catch {
                _ = res.status(404);
                res.text("Invalid ID") catch {};
                return;
            };
            const row = query.getById(M, db, gpa, id) catch {
                _ = res.status(404);
                res.text("Not Found") catch {};
                return;
            };
            defer query.freeRow(M, gpa, @constCast(&row));

            // ── try template rendering ─────────────────────────────────
            if (admin_engine) |engine| {
                var ctx = Context.init(gpa);
                defer ctx.deinit();
                ctx.put("_csrf", .{ .string = csrf.generateToken() }) catch {};
                ctx.put("table_name", .{ .string = M.table_name }) catch {};
                if (renderTmpl(engine, res, "admin/confirm_delete.html", &ctx)) return;
            }

            // ── fallback inline HTML ───────────────────────────────────
            var html: std.ArrayList(u8) = .empty;
            defer html.deinit(gpa);
            html.appendSlice(gpa, "<!DOCTYPE html><html><head><title>Delete ") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "</title><meta name=\"viewport\" content=\"width=device-width\"><style>*{box-sizing:border-box}body{font-family:system-ui,sans-serif;max-width:640px;margin:2em auto;padding:0 1em}button{padding:.5em 1em;cursor:pointer}</style></head><body><h1>Confirm Delete</h1><p>Are you sure?</p><form method=\"post\" style=\"display:inline\"><input type=\"hidden\" name=\"_csrf\" value=\"") catch return;
            html.appendSlice(gpa, csrf.generateToken()) catch return;
            html.appendSlice(gpa, "\"><button type=\"submit\" style=\"background:#d73a49;color:white;border:none\">Delete</button></form> <a href=\"/admin/") catch return;
            html.appendSlice(gpa, M.table_name) catch return;
            html.appendSlice(gpa, "/\">Cancel</a></body></html>") catch return;
            const owned = html.toOwnedSlice(gpa) catch return;
            res.body = owned;
            _ = res.header("Content-Type", "text/html; charset=utf-8");
        }
    };
    return H.handle;
}

fn deleteHandler(comptime M: type) *const fn (*Request, *Response) void {
    const H = struct {
        fn handle(req: *Request, res: *Response) void {
            if (!requireAdmin(req, res)) return;
            if (!validateCsrf(req)) {
                _ = res.status(403);
                res.text("CSRF token missing or invalid") catch {};
                return;
            }
            const db = admin_db orelse {
                _ = res.status(500);
                res.text("Admin: no database") catch {};
                return;
            };
            const id_str = req.params.get("id") orelse {
                _ = res.status(404);
                res.text("Not Found") catch {};
                return;
            };
            const id = std.fmt.parseInt(i64, id_str, 10) catch {
                _ = res.status(404);
                res.text("Invalid ID") catch {};
                return;
            };
            query.deleteById(M, db, id) catch {
                _ = res.status(500);
                res.text("Admin: delete failed") catch {};
                return;
            };
            res.redirect("/admin/" ++ M.table_name ++ "/", 302) catch {};
        }
    };
    return H.handle;
}

test {
    std.testing.refAllDecls(@This());
}
