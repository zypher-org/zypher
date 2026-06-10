# CLI API

## Runner
CLI command dispatcher.

- `dispatchInner(out, err, init, cmd, args)` — Dispatch a CLI command
- `RunserverConfig` — Server configuration struct
- `parseRunserverConfig(args)` — Parse runserver arguments
- `runserverDefaultHandler(req, res)` — Default health check handler
- `bindRunserverSignalTarget(app, io)` — Bind signal handler target
- `clearRunserverSignalTarget()` — Clear signal handler target

### Commands
- `new <name>` — Scaffold a new project
- `demo <name>` — Create a demo project with template
- `runserver` — Start HTTP server
- `migrate` — Run database migrations
- `makemigrations` — Generate migration files
- `createsuperuser` — Create admin user
- `shell` — Interactive REPL
- `help` — Show help
