# CLI API

## Runner
CLI command dispatcher.

- `dispatchInner(out, err, init, cmd, args)` — Dispatch a CLI command
- `buildRunArgv(gpa, zypher_root, app_args)` — Build the `zig build run` argv used by `zypher run`
- `RunserverConfig` — Server configuration struct
- `parseRunserverConfig(args)` — Parse runserver arguments
- `runserverDefaultHandler(req, res)` — Default health check handler
- `bindRunserverSignalTarget(app, io)` — Bind signal handler target
- `clearRunserverSignalTarget()` — Clear signal handler target

### Commands
- `new <path> [--template <name>] [--template-dir <dir>]` — Scaffold a new project from a template
- `templates [--template-dir <dir>]` — List available scaffold templates
- `run [path] [--zypher-root <path>] [-- <app args...>]` — Run a scaffolded app through its `build.zig`
- `demo <path>` — Compatibility alias that scaffolds the `mvc` template
- `runserver [--host <host>] [--port <port>] [--max-requests <n>]` — Start the framework health-check server
- `migrate [--db <path>] [--dir <dir>]` — Run database migrations
- `makemigrations [--schema <path>] [--state <path>] [--dir <dir>]` — Generate migration files
- `createsuperuser [--username <email>] [--password <password>] [--db <path>]` — Create an admin user
- `shell` — Interactive REPL
- `help` — Show help

## Project Scaffolding

`zypher new` accepts either a bare project name or a nested path:

```sh
zypher new blog
zypher new examples/blog --template clean-arch
```

The project name used in template substitutions is the basename of the path. For `examples/blog`, `{{project_name}}` becomes `blog`.

Built-in templates are stored under the repository root `templates/` directory:

- `single-file`
- `clean-arch`
- `mvc`
- `mvp`

Templates are copied recursively. File paths and file contents may use `{{project_name}}`; the CLI replaces it during scaffold creation. This keeps third-party templates simple: place a folder under a template directory and pass it with `--template-dir`.

Every built-in template includes:

- `build.zig`
- a runnable Zypher app
- a sample `managed_items` ORM model
- `zypher.admin.AdminSite` registration
- `/admin` redirecting to `/admin/login`
- `/admin/login` credentials backed by the `users` table created by `zypher createsuperuser`

## Running Scaffolded Apps

`zypher run` delegates to the generated app build script:

```sh
zypher run .
zypher run examples/blog --zypher-root ../..
zypher run . -- --port 9000
```

It runs:

```sh
zig build -Dzypher-root=<path> run
```

Generated `build.zig` files default `zypher-root` to `../..`, which matches apps created under `examples/`. Pass `--zypher-root` for apps elsewhere.
