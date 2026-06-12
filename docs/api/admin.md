# Admin API

Auto-generated CRUD interface for registered ORM models. Admin panel provides list, add, change, and delete views with pagination, search, and CSRF protection.

## AdminModelOptions
Per-model configuration for the admin interface:
- `verbose_name_plural: ?[]const u8 = null` — plural display name (defaults to table name)
- `list_display: []const []const u8 = &.{}` — fields to display in list view (currently unused; all fields shown)
- `search_fields: []const []const u8 = &.{}` — fields searchable (currently unused; scaffolding placeholder)
- `list_per_page: usize = 25` — pagination page size

## Registration(Model, options) type
Wrap an ORM model and admin options into a type suitable for `AdminSite` configuration:

```zig
const reg = Registration(MyModel, .{
    .verbose_name_plural = "My Models",
    .list_per_page = 10,
});
```

## AdminSite(config) type
Build a comptime admin site from registered models.

### Configuration
```zig
const site = AdminSite(.{
    .items = Registration(ItemModel, .{}),
    .users = Registration(UserModel, .{ .verbose_name_plural = "Users" }),
});
```

### Model Metadata
- `site.model_names` — array of field names in the config tuple
- `site.model_count` — number of registered models
- `site.meta` — array of `ModelMeta` structs with `table_name`, `verbose_name_plural`, `list_display`, `search_fields`, `list_per_page`, `field_count`
- `site.modelInfo(table) ModelMeta` — get metadata for a specific table name (comptime error if unknown)

### Methods
- `AdminSite.routes()` — generate CRUD routes for every registered model:
  - `GET /admin/` — index page listing all registered models
  - `GET /admin/{table}/` — list view with paginated rows
  - `GET /admin/{table}/add/` — add form
  - `POST /admin/{table}/add/` — create handler
  - `GET /admin/{table}/:id/change/` — edit form
  - `POST /admin/{table}/:id/change/` — update handler
  - `GET /admin/{table}/:id/delete/` — confirm delete page
  - `POST /admin/{table}/:id/delete/` — delete handler
- `AdminSite.loadTemplates(engine)` — load built-in admin templates (base.html, index.html, list.html, form.html, confirm_delete.html) into a `TemplateEngine`

### Thread-local Functions
- `setDb(db: *sqlite.Db)` — bind the SQLite connection used by admin handlers
- `setEngine(engine: *TemplateEngine)` — bind the template engine used by admin handlers

## Access Control
Admin handlers require a session with `role=admin`:
- If `req.user` is null → 302 redirect to `/admin/login`
- If session `role` is not `"admin"` → 403 Forbidden
- All mutation handlers (POST) validate CSRF via `_csrf` form value

## Generated Routes per Model
Each registered model gets 7 routes:
1. `GET /admin/{table}/` — list with pagination (reads `page` query param, default 1)
2. `GET /admin/{table}/add/` — add form with CSRF token
3. `POST /admin/{table}/add/` — create record (validates CSRF, reads form values by field name)
4. `GET /admin/{table}/:id/change/` — edit form pre-filled with existing data
5. `POST /admin/{table}/:id/change/` — update record (validates CSRF)
6. `GET /admin/{table}/:id/delete/` — confirm delete page
7. `POST /admin/{table}/:id/delete/` — delete record (validates CSRF)

## Template Rendering
Admin tries to use templates first (if `setEngine` was called), then falls back to inline HTML. Built-in templates:
- `admin/base.html` — base layout
- `admin/index.html` — model list page
- `admin/list.html` — paginated record list
- `admin/form.html` — add/edit form
- `admin/confirm_delete.html` — delete confirmation

## Audit Logging
All mutation operations (create, update, delete) log the acting username and affected record via `std.log.scoped(.admin)`.

## Scaffolded Admin
Every built-in CLI template registers a sample `managed_items` ORM model so `/admin/` is immediately usable. The scaffold also includes:
- `/admin/login` — login form backed by `users` table (created by `zypher createsuperuser`)
- `/admin/forgot-password` — email-based 6-digit recovery code
- `/admin/reset-password` — reset password with recovery code

## Full Example
```zig
const zypher = @import("zypher");

const MyModel = zypher.Model("items", .{
    zypher.Field("id", .integer, .{ .primary = true }),
    zypher.Field("name", .text, .{ .required = true }),
    zypher.Field("price", .float, .{}),
});

const my_admin = zypher.AdminSite(.{
    .items = zypher.Registration(MyModel, .{
        .verbose_name_plural = "Items",
    }),
});

// Create router and register admin routes
const routes = comptime blk: {
    var site_routes = my_admin.routes();
    break :blk site_routes;
};

var router = zypher.Router.init(routes, notFound);
app.routerHandler(router.dispatch);

// Bind thread-local resources
zypher.setDb(&db);
zypher.setEngine(&engine);
my_admin.loadTemplates(&engine);
```
