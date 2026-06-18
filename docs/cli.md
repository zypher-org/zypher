# CLI API

## Runner
CLI command dispatcher with subcommands for project scaffolding, running, documentation, migrations, and admin tasks.

### Key Functions
- `dispatchInner(out, err, init, cmd, args, version) !void` — dispatch a CLI command by name
- `buildRunArgv(gpa, zypher_root, port, app_args) ![]const [:0]const u8` — build `zig build run` argv for `zypher run`
- `buildDocArgv(gpa, zypher_root, project_path, host, port, max_requests) ![]const [:0]const u8` — build `zig build doc` argv for documentation commands

### RunserverConfig
- `host: []const u8 = "127.0.0.1"` — bind address
- `port: u16 = 8080` — listen port
- `max_requests: ?usize = null` — optional request limit

### Helpers
- `parseRunserverConfig(args) RunserverConfig` — parse runserver arguments
- `runserverDefaultHandler(req, res)` — default health-check handler (returns 404)
- `sigint_app` — pointer to the active `*App`, set during runserver/docs-server; the SIGINT handler in `cli/main.zig` reads this to call `app.shutdown(io)`.

## Commands

### Project Scaffolding
- `zypher new <path> [--template <name>] [--api] [--template-dir <dir>]` — scaffold a new project from a template
  - Project name is basename of path
  - `{{project_name}}` is replaced in file paths and contents
  - `--api` appends `-api` to template name
  - Falls back to embedded templates if template dir not found

- `zypher templates [--template-dir <dir>]` — list available templates
- `zypher demo <name>` — compatibility alias for `zypher new <name> --template mvc`

### Running Apps
- `zypher run [path] [--zypher-root <path>] [--port <port>] [-- <app args...>]` — run a scaffolded app through its `build.zig`
  - Infers zypher root from binary location, package install paths, or current checkout
  - Honors `ZYPHER_ROOT` environment variable
  - Defaults to port 8080
  - Delegates to `zig build -Dzypher-root=<path> run`

### Development Server
- `zypher runserver [--host <host>] [--port <port>] [--max-requests <n>]` — start the framework health-check server

### Documentation
- `zypher doc [--zypher-root <path>] [--host <host>] [--port <port>] [--max-requests <n>]` — build and serve Zypher library documentation
- `zypher doc-user [path] [--host <host>] [--port <port>] [--max-requests <n>]` — build and serve documentation for user code

### Database
- `zypher migrate [--db <path>] [--dir <dir>]` — run pending SQL migrations from a directory
  - Collects `.sql` files, sorts by name, applies unapplied ones
  - Tracks applied migrations in `zypher_migrations` table
- `zypher makemigrations [--schema <path>] [--state <path>] [--dir <dir>]` — generate migration files by comparing schema manifest to previous state

### Admin
- `zypher createsuperuser [--username <name>] [--email <email>] [--password <password>] [--db <path>]` — create an admin user in the database
  - Interactive mode with hidden password input if any field is omitted
  - Validates: non-empty username, valid email, password ≥ 8 chars with letter + digit
  - Creates `users` table if it doesn't exist (with email, reset_code, reset_code_expires_at columns)
  - Stores password as PBKDF2-HMAC-SHA256 hash
  - Sets role to `"admin"`
  - Supports `--db` (default: `db.sqlite`)

### Shell
- `zypher shell [--eval <expr>]` — interactive REPL with integer arithmetic
  - Commands: `:help`, `:context`, `:contract`, `:quit`
  - Supports `+`, `-`, `*`, `/` operators

### Help
- `zypher help` — show available commands

## Built-in Templates
Templates are embedded into the binary at compile time. Each style has an HTML variant and an API variant:
- `single-file` / `single-file-api`
- `clean-arch` / `clean-arch-api`
- `mvc` / `mvc-api`
- `mvp` / `mvp-api`

### Every template includes:
- `build.zig` with `-Dzypher-root` support
- A runnable Zypher app
- Sample `managed_items` ORM model
- `AdminSite` registration
- `/admin` redirecting to `/admin/login`
- `/admin/login` backed by `users` table
- `/admin/forgot-password` and `/admin/reset-password` with 6-digit recovery codes

API variants return JSON for app routes instead of HTML templates.

## Installation
```sh
zig build
export PATH="$PWD/zig-out/bin:$PATH"
zypher help
```

Published installs use the Zig version pinned in `build.zig.zon`, place that toolchain under `~/.zypher/zig`, and install the matching Zypher source tree under `~/.zypher/source`.
