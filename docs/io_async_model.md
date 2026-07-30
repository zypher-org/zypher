# std.Io Async/Concurrent Model

> Phase 14 — classification guide, cancel contract, backend construction site rule.

## `io.async()` vs `io.concurrent()` — The One-Sentence Rule

- **`io.async(fn, args)`** — "I don't need a separate thread; if the backend can overlap this work, great; otherwise run it inline." Use for asynchrony-without-parallelism: body parsing while route matching, independent sub-operations in a handler. Under `init_single_threaded`, `io.async()` runs the function inline and returns a completed `Future`.
- **`io.concurrent(fn, args)`** — "I require true parallelism: the caller and this task must advance simultaneously." Use for the server accept loop vs connection handlers. Under `init_single_threaded`, `io.concurrent()` returns `error.ConcurrencyUnavailable` — the caller must handle this with a sequential fallback.

## Audit: Current Call Sites

The grep of `src/` for `io\.async\(` and `io\.concurrent\(` found **zero actual call sites** as of Phase 14 start. All future spawn points are marked as `TODO` comments in `src/core/server.zig`:

| File | Line | Function | TODO Scope | Correct Classification |
|------|------|----------|------------|----------------------|
| `src/core/server.zig` | 124, 157 | `listenAndServe` | Replace inline serving with `io.concurrent()` | **concurrent** — accept loop and handler must advance in parallel |
| `src/core/server.zig` | 172 | `handleConnection` | Future `io.concurrent/Future` compatibility | **async** — within a single connection, body parsing and route matching can overlap |

The only `io.*` async-related call sites currently active are:

| File | Line | Function | Call | Purpose |
|------|------|----------|------|---------|
| `src/core/server.zig` | 137 | `listenAndServe` | `io.checkCancel()` | Cooperative cancellation check in accept loop |
| `src/core/server.zig` | 192 | `handleConnection` | `io.checkCancel()` | Cooperative cancellation check per request |
| `src/core/util.zig` | — | `randomBytes` | `io.random(buf)` | CSPRNG access |

## The Cancellation Contract

Every `io.async()` and `io.concurrent()` call MUST be immediately followed by:

```zig
defer future.cancel(io) catch {};
```

**Why:** `std.Io.Threaded` allocates an async closure on the heap via the provided allocator. If the scope exits before `future.await(io)` is called (e.g. due to an early return), the closure is leaked unless `future.cancel(io)` is called. `std.testing.allocator` will report this as a leak.

### Correct Pattern

```zig
var fut = io.async(workFn, .{arg1, arg2});
defer fut.cancel(io) catch {};

// ... other work that may return early ...

const result = fut.await(io);
try result;
```

### Incorrect Pattern (Leak)

```zig
// BAD: No defer cancel — early return leaks the async closure.
var fut = io.async(workFn, .{arg1, arg2});
const interim = try fallibleOp();
const result = try fut.await(io);
```

## The "Collect-Results-Then-Try" Pattern

When spawning multiple concurrent tasks, always collect results before inspecting errors:

```zig
var a = io.async(taskA, .{});
defer a.cancel(io) catch {};
var b = io.async(taskB, .{});
defer b.cancel(io) catch {};

const a_result = a.await(io);
const b_result = b.await(io);
try a_result;  // if this fails, b_result's cancel already ran via defer
try b_result;
```

Never `try a.await(io)` before calling `b.await(io)` — if `a` fails, `b`'s defer cancel hasn't fired yet and the async closure leaks.

## Choosing a Backend

| Backend | When to use | Parallelism | Platform support |
|---------|-------------|-------------|------------------|
| `single_threaded` | embedded, testing, single-core targets | none | all |
| `threaded` (default) | desktop apps, web servers, databases | OS thread pool | all |
| `evented` | high-throughput servers (10k+ conns) | fibers + io_uring/GCD | Linux (io_uring), macOS (GCD) — experimental |

## Backend Construction Site

Only two files in the codebase may reference `std.Io.Threaded` or `std.Io.Evented` by name:

```
src/core/io_backend.zig     ← ZypherIo union: init, io(), deinit
src/cli/main.zig            ← binary entry point: constructs ZypherIo, forwards io
```

All other files receive `io: std.Io` as a parameter and do not know which backend is in use. This invariant is enforced by CI (`zig build test-backend-construction-site` in `.github/workflows/ci.yml`).

## `std.Io.Evented` Status in 0.16

`std.Io.Evented` (io_uring on Linux, Grand Central Dispatch on macOS) is **experimental**. Networking may return `error.NetworkDown` on some platforms. To opt in:

```bash
zig build -Dio_evented=true
```

Without this flag, `AppConfig.io_backend = .evented` triggers a `@compileError` with instructions.

## Known Gaps

*(To be filled as Phase 14 tasks complete; should be empty by the end of Phase 14.)*
