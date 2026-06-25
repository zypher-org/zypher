# std.Io Interface Migration

> **Phase 12** of the zypher framework replaced all direct OS-specific I/O calls with Zig's `std.Io` abstraction. After this phase, no zypher library source file reaches into `std.posix`, `std.net`, `std.os.linux`, `std.time.Instant`, `std.Thread.Pool`, `std.io.GenericReader`/`AnyReader`, `std.io.GenericWriter`/`AnyWriter`, `std.io.FixedBufferStream`, or `std.io.getStd*`.

## Invariant

**`std.Io` is always caller-supplied.** No zypher library source file (outside `src/cli/main.zig`) may construct, own, or default-initialise an `std.Io` instance. Every module receives `io: std.Io` as a parameter — exactly as `Allocator` flows through every allocation-aware API.

This means users can pass any conforming `std.Io` backend (`std.Io.Threaded`, `std.Io.Uring`, `std.Io.Dispatch`, or a future `std.Io.Evented`) without altering a single line of framework code.

## Functions That Gained `io: std.Io`

### Core HTTP

| Module | Function | `io` Position | Notes |
|--------|----------|---------------|-------|
| `Server` | `listenAndServe` | 2nd (after `self`) | Binds TCP, accepts connections, dispatches handler |
| `Server` | `shutdown` | 1st | Cancels accept loop, closes listener |
| `App` | `listenAndServe` | 2nd (after `self`) | Forwards `io` to `Server.listenAndServe` |
| `App` | `shutdown` | 2nd (after `self`) | Forwards to `Server.shutdown` |
| `Request` | (via `Server.buildRequest`) | (internal) | Parsing uses `std.Io.Reader` |
| `Response` | `send` | 2nd (after `self`) | Takes `*std.Io.Writer` for serialisation |
| `Response` | `sendHeaders` | (internal) | Takes `*std.Io.Writer` |
| `Server.HandlerFn` | — | none | Terminal handler does NOT receive `io` (unlike middleware) |

### Middleware

| Module | Function | `io` Position | Notes |
|--------|----------|---------------|-------|
| `MiddlewareFn` | — | 1st | `fn (std.Io, *Request, *Response, NextFn) void` |
| `NextFn` | — | 1st | `fn (std.Io, *Request, *Response) void` |
| `Chain` | `run` | 1st | Passes through the entire middleware pipeline |
| `Logger` | (middleware) | 1st | `std.Io.Timestamp.now(io, .awake)` for duration |
| `RateLimit` | (middleware) | 1st | `std.Io.Timestamp.now(io, .real)` for window expiry |
| `StaticFile` | (middleware) | 1st | File open/read/stat/close via `std.Io.File` |
| `Compress` | (middleware) | (internal) | Streams gzip output to `*std.Io.Writer` |
| `Session` | (middleware) | 1st | Forwards `io` to `SessionStore.create/get` |

### Template Engine

| Module | Function | `io` Position | Notes |
|--------|----------|---------------|-------|
| `TemplateEngine` | `load` | 2nd (after `self`) | Reads template source via `std.Io.Dir.cwd().readFileAlloc` |
| `TemplateEngine` | `render` | 1st | Writes rendered output to `*std.Io.Writer.Interface` |
| `Template` | `render` | (none) | Pure rendering — no `io` needed |

### ORM / Migrations

| Module | Function | `io` Position | Notes |
|--------|----------|---------------|-------|
| `MigrationRunner` | `migrate` | 3rd (after `self`, `migrations`) | Placeholder for future file-based migration I/O |
| `sqlite.Db` | `open` | (via `io.random`) | CSPRNG for temporary names if needed |

### Auth

| Module | Function | `io` Position | Notes |
|--------|----------|---------------|-------|
| `password.hash` | — | 1st | `io.random(buf)` for salt generation |
| `User.init` | — | 1st | Forwards to `password.hash` |
| `SessionStore.create` | — | 2nd (after `self`) | Forwards to `util.randomBytes(io, &id)` |
| `SessionStore.get` | — | 3rd (after `self`, `raw_id`) | Forwards to `isExpired(io)` |
| `Session.isExpired` | — | 2nd (after `self`) | `Io.Timestamp.now(io, .real)` for expiry check |

### CLI Subcommands

| Module | Function | `io` Position | Notes |
|--------|----------|---------------|-------|
| `main` | CLI entry | `std.process.Init` | Juicy Main — `init.io` forwarded to all subcommands |
| `runserver` | — | from `init` | Forwards to `App.listenAndServe` |
| `migrate` | — | from `init` | Forwards to `MigrationRunner.migrate` |
| `createsuperuser` | — | from `init` | Replaces `std.io.getStdIn()` with `std.Io.File.stdin()` |
| `shell` | — | from `init` | Replaces `std.io.getStdIn/Out` with `std.Io.File.stdin/stdout` |

## Removed OS Primitives

| Category | Removed Calls | Replacement |
|----------|---------------|-------------|
| `std.posix` | `clock_gettime`, `sigaction`, `tcgetattr`/`tcsetattr`, `read`, `write` | `std.Io.Timestamp.now`, `App.shutdown`, `std.Io.File` methods |
| `std.net` | `StreamServer`, `Address` | `std.Io.net.Server`, `std.Io.net.IpAddress` |
| `std.os.linux` | (implicit through `std.posix`) | — |
| `std.time.Instant` | `now()`, duration arithmetic | `std.Io.Timestamp.now`, `std.Io.Duration` |
| `std.Thread.Pool` | (was internally used) | `std.Io.Threaded` or caller-provided `std.Io` backend |
| `std.io.GenericReader` / `AnyReader` | `Request.parse` | `*std.Io.Reader.Interface` |
| `std.io.GenericWriter` / `AnyWriter` | `Response.send` | `*std.Io.Writer` |
| `std.io.FixedBufferStream` | Response body buffering | Stack-allocated arrays + `std.Io.Writer.fixed` |
| `std.io.getStdIn` / `getStdOut` | CLI subcommands | `std.Io.File.stdin().reader(io, &buf)` / `stdout()` |

## CI Guard

The `zig build test-io-clean` step runs a grep for all forbidden OS primitives across `src/`. Exclusions:

- `src/orm/` — SQLite C FFI bindings (io-neutral C externs)
- `src/cli/embedded_templates.zig` — Auto-generated template string literals
- `src/cli/main.zig` — SIGINT sigaction (binary entry-point responsibility)
- `src/cli/runner.zig` — Terminal tcgetattr/tcsetattr (interactive shell REPL)
- Doc/comment lines (lines starting with `//`) — documentation references

## Example: Using zypher with a custom `std.Io` backend

```zig
const std = @import("std");
const zypher = @import("zypher");

pub fn main(init: std.process.Init) !void {
    const io = init.io; // caller-supplied Io
    var app = zypher.core.App.init(init.gpa, .{ .port = 8080 });
    defer app.deinit();

    app.handler(struct {
        pub fn handle(req: *zypher.core.Request, res: *zypher.core.Response) void {
            _ = req;
            res.text("Hello, world!") catch {};
        }
    }.handle);

    try app.listenAndServe(io);
}
```

## IO Configuration API

zypher provides a unified API for IO configuration through `zypher.core.IoConfig`:

### Available IO Models

- **`.default`** - Uses the IO backend provided by `std.process.Init` (recommended for most cases)
- **`.custom`** - Use a custom user-provided `std.Io` instance

### Usage Examples

#### Using Default IO (recommended)

```zig
const std = @import("std");
const zypher = @import("zypher");

pub fn main(init: std.process.Init) !void {
    const io_config = zypher.core.IoConfig.default();
    const io = try io_config.createIo(init);
    
    var app = zypher.core.App.init(init.gpa, .{ .port = 8080 });
    defer app.deinit();
    
    app.handler(myHandler);
    try app.listenAndServe(io);
}
```

#### Using Custom IO

For advanced use cases, you can provide your own `std.Io` instance:

```zig
const std = @import("std");
const zypher = @import("zypher");

pub fn main(init: std.process.Init) !void {
    var my_custom_io = createCustomIoBackend(); // Your custom implementation
    const io_config = zypher.core.IoConfig.custom(my_custom_io);
    const io = try io_config.createIo(init);
    
    var app = zypher.core.App.init(init.gpa, .{ .port = 8080 });
    defer app.deinit();
    
    app.handler(myHandler);
    try app.listenAndServe(io);
}
```

### Note on Advanced IO Backends

For advanced IO backends like `std.Io.Threaded`, `std.Io.Uring`, or `std.Io.Dispatch`, these require manual initialization with an `Evented` instance. Users who need these backends should initialize them manually and pass the resulting `std.Io` instance via `IoConfig.custom()`. This maintains the framework's invariant that `std.Io` is always caller-supplied while allowing full flexibility for advanced use cases.
