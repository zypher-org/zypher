# CLI API

## Runner
CLI command dispatcher.

Build the CLI once from the repository root, then use `zypher` for project workflows:

```sh
zig build
export PATH="$PWD/zig-out/bin:$PATH"
zypher help
```

- `dispatchInner(out, err, init, cmd, args)` — Dispatch a CLI command
- `buildRunArgv(gpa, zypher_root, app_args)` — Build the `zig build run` argv used by `zypher run`
- `buildDocArgv(gpa)` — Build the `zig build doc` argv used by documentation commands
- `RunserverConfig` — Server configuration struct
- `parseRunserverConfig(args)` — Parse runserver arguments
- `runserverDefaultHandler(req, res)` — Default health check handler
- `bindRunserverSignalTarget(app, io)` — Bind signal handler target
- `clearRunserverSignalTarget()` — Clear signal handler target

### Commands
- `new <path> [--template <name>] [--api] [--template-dir <dir>]` — Scaffold a new project from a template
- `templates [--template-dir <dir>]` — List available scaffold templates
- `run [path] [--zypher-root <path>] [--port <port>] [-- <app args...>]` — Run a scaffolded app through its `build.zig`; the Zypher root is inferred by default
- `doc [--zypher-root <path>] [--host <host>] [--port <port>] [--max-requests <n>]` — Build and serve Zypher library documentation
- `doc-user [path] [--host <host>] [--port <port>] [--max-requests <n>]` — Build and serve documentation for user code
- `demo <path>` — Compatibility alias that scaffolds the `mvc` template
- `runserver [--host <host>] [--port <port>] [--max-requests <n>]` — Start the framework health-check server
- `migrate [--db <path>] [--dir <dir>]` — Run database migrations
- `makemigrations [--schema <path>] [--state <path>] [--dir <dir>]` — Generate migration files
- `createsuperuser [--username <name>] [--email <email>] [--password <password>] [--db <path>]` — Create an admin user
- `shell` — Interactive REPL
- `help` — Show help

## Project Scaffolding

`zypher new` accepts either a bare project name or a nested path:

```sh
zypher new blog
zypher new examples/blog --template clean-arch
zypher new services/books --template mvc --api
```

The project name used in template substitutions is the basename of the path. For `examples/blog`, `{{project_name}}` becomes `blog`.

Built-in templates are stored under the repository root `templates/` directory. Each style has an HTML/template-oriented variant and an API variant:

- `single-file`
- `single-file-api`
- `clean-arch`
- `clean-arch-api`
- `mvc`
- `mvc-api`
- `mvp`
- `mvp-api`

`--api` maps the selected template to its `-api` sibling. For example, `--template mvc --api` scaffolds `mvc-api`.

Templates are copied recursively. File paths and file contents may use `{{project_name}}`; the CLI replaces it during scaffold creation. This keeps third-party templates simple: place paired folders under a template directory and pass it with `--template-dir`.

Every built-in template includes:

- `build.zig`
- a runnable Zypher app
- a sample `managed_items` ORM model
- `zypher.admin.AdminSite` registration
- `/admin` redirecting to `/admin/login`
- `/admin/login` credentials backed by the `users` table created by `zypher createsuperuser`
- `/admin/forgot-password` and `/admin/reset-password` for 6-digit recovery codes

API variants do not include project HTML templates for app routes. Their app routes return JSON with `Response.json`; the admin dashboard still uses the framework's built-in admin templates.

## Superusers

`zypher createsuperuser` creates the admin row used by scaffolded `/admin/login` routes. The default flow is interactive:

```sh
zypher createsuperuser --db app.db
```

It prompts for username, email, password, and password confirmation. Password input is hidden in an interactive terminal.

For scripts or fixtures, pass all account fields explicitly:

```sh
zypher createsuperuser --username admin --email admin@example.com --password Passw0rd --db app.db
```

Scaffolded admin login uses `username` and `password`. Password recovery uses the stored email address: `POST /admin/forgot-password` creates a 6-digit code, and `POST /admin/reset-password` accepts `email`, `code`, `password`, and `confirm_password`.

## Running Scaffolded Apps

`zypher run` is the supported way to start scaffolded apps from the CLI. It delegates to the generated app build script and forwards runtime options:

```sh
zypher run .
zypher run examples/blog
zypher run . --port 9000
```

It runs:

```sh
zig build -Dzypher-root=<path> run -- --port <port>
```

`zypher run` passes the Zypher source root to the generated build script automatically. It infers that root from the CLI binary when the binary lives under `zig-out/bin`, and falls back to the current framework checkout when run from the repository root. Pass `--zypher-root` only for nonstandard installs. If `--port` is omitted, `zypher run` forwards `--port 8080`; generated apps also default to `8080` when run directly without a port. Users should prefer `zypher run` over invoking the app build script directly.

## Documentation Server

`zypher doc` is the CLI entrypoint for framework documentation. It builds the framework docs and serves the generated `zig-out/docs` directory:

```sh
zypher doc
zypher doc --zypher-root /path/to/zypher --port 9000
```

`zypher doc-user` is the CLI entrypoint for user-project documentation. It builds docs for the current project or a selected project path and serves that project's `zig-out/docs` directory:

```sh
zypher doc-user
zypher doc-user examples/books-api --port 9001
```

Both commands default to `127.0.0.1:8080` and accept `--max-requests` for tests or one-shot smoke checks.
