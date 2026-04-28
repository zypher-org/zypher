# zypher Architecture

## Error Propagation Convention

All zypher subsystem errors are namespaced under `ZypherError` (defined in `src/errors.zig`).

### Rules

1. **Use `ZypherError!T` for all public API return types.** Never use ad-hoc error sets.
2. **Propagate with `try`.** Never swallow errors silently. If recovery is needed, use `catch |err|` with explicit handling.
3. **Convert external errors at subsystem boundaries.** When a subsystem calls into `std`, SQLite, or any external API, catch the external error and map it to the appropriate `ZypherError` variant:

   ```zig
   fn connectDb(path: []const u8) ZypherError!*Db {
       const db = sqlite.open(path) catch return error.DbConnectionFailed;
       return db;
   }
   ```

4. **Log before returning errors.** At subsystem boundaries, log the error with context before propagating:

   ```zig
   fn handleRequest(req: *const Request) ZypherError!Response {
       const result = parseBody(req) catch |err| {
           log.writeLog(.err, "request", "parse failed");
           return err; // already a ZypherError
       };
       // ...
   }
   ```

5. **Never use `unreachable` for error conditions.** `unreachable` is only for logically impossible states. Use `error.Xyz` for anything that can fail at runtime.

6. **Error-to-string mapping.** Use `errors.errorToString(err)` for user-facing messages. The mapping is exhaustive and maintained alongside the error set.

### Error Categories

| Category | Prefix | Example |
|---|---|---|
| Core / HTTP | (none) | `BadRequest`, `NotFound` |
| Router | (none) | `InvalidRoutePattern`, `AmbiguousRoute` |
| Middleware | (none) | `CsrfValidationFailed`, `CorsBlocked` |
| Template | (none) | `TemplateNotFound`, `TemplateSyntaxError` |
| ORM / Database | `Db` | `DbConnectionFailed`, `DbQueryFailed` |
| Forms / Validation | `Field` / `Invalid` | `FieldRequired`, `InvalidEmail` |
| Auth | (none) | `AuthenticationFailed`, `SessionInvalid` |
| Admin | `Admin` | `AdminModelNotRegistered` |
| CLI | (none) | `UnknownCommand`, `InvalidArguments` |
