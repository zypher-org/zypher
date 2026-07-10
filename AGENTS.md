# Zypher IO & Threading Policy

## Core Principle
All I/O in `src/` (the library) must flow through the injected `std.Io` vtable.
The library must never call OS primitives (posix, Thread, net without Io) directly.

## What's Allowed
- `std.Io` and all its sub-namespaces (`std.Io.net.*`, `std.Io.File.*`, etc.)
- `threadlocal` variables for context passing (they don't import `std.Thread`, work correctly with `-fsingle-threaded`, and are the only way to pass runtime state through the fixed-signature handler/middleware functions in Zig)
- `std.c.*` for synchronous C library calls in database drivers (excluded from IO-clean audit via `--exclude-dir`)
- `std.fs` path string operations (no actual I/O)
- `std.time` epoch utilities (not `std.time.Instant`)

## What's Forbidden in `src/`
- `std.Thread` — any usage (spawn, yield, getCpuCount, Pool)
- `std.posix` — direct POSIX syscalls
- `std.net` (without Io) — direct networking
- `std.os.linux` — Linux-specific syscalls
- `std.time.Instant` — must use `std.Io.Timestamp`
- `std.io.GenericReader` / `AnyReader` / `FixedBufferStream` — must use `std.Io.Reader` / `Writer`
- `std.io.getStd*` — must use `std.Io.File.stdin/stdout/stderr`

## Enforcement
The `test-io-clean` build step runs a grep for all forbidden patterns across `src/`.
Database drivers (`orm/driver/`, `orm/document/`, `orm/kv/`) and generated template code
are excluded. The CLI binary entry points (`main.zig`, `runner.zig`) are excluded
because they need posix for signal handling/terminal I/O on POSIX platforms (these
calls are comptime-gated to non-Windows/non-WASI).

## Default Backend
The server default is `IoBackend.single_threaded` (no thread pool).
Use `.threaded` or `.evented` explicitly for multi-threaded or io_uring-based I/O.

## Threadlocal Notes
`threadlocal` is a Zig language keyword, not a std import. It does not create threads
or call POSIX syscalls. In single-threaded builds (`-fsingle-threaded`), threadlocal
variables behave identically to regular globals. They are used for:
- `chain.zig`: Passing the terminal handler through middleware dispatch (Zig lacks closures)
- `middleware/session.zig`, `csrf.zig`, `security_headers.zig`: Config/context for middleware
- `auth/user.zig`: Io reference for handler functions
- `admin/registry.zig`: DB connection for admin CRUD handlers

These are acceptable in the current single-threaded architecture. If the evented
backend becomes the default, they should be replaced with fiber-local storage
or explicit context structs.
