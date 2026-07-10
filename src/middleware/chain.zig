/// zypher middleware pipeline — comptime chain with runtime dispatch.
///
/// Since Zig has no closures, the `next` callback problem is solved by
/// generating the entire dispatch chain at comptime. Each Chain type
/// has its run method fully unrolled, so middleware[i] calls a
/// comptime-known next that calls middleware[i+1], and so on.
///
/// The terminal handler is passed at runtime via a thread-local variable,
/// since inner functions cannot capture outer parameters.
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const log = std.log.scoped(.middleware);

/// Type for the `next` callback passed to each middleware.
/// The std.Io instance is the first parameter.
pub const NextFn = *const fn (std.Io, *Request, *Response) void;

/// Type for a middleware function.
/// The std.Io instance is the first parameter, followed by request, response, and next callback.
pub const MiddlewareFn = *const fn (std.Io, *Request, *Response, NextFn) void;

/// Handler function type (terminal handler at the end of the chain).
pub const HandlerFn = *const fn (*Request, *Response) void;

/// Comptime middleware chain. Middleware is registered at comptime;
/// dispatch is runtime with zero heap allocation.
///
/// Usage:
///   const MyChain = comptime Chain(.{ mw_logger, mw_cors });
///   MyChain.run(&req, &res, handler, io);
pub fn Chain(comptime mws: anytype) type {
    comptime {
        // Validate all items are functions or function pointers
        for (mws, 0..) |mw, i| {
            const T = @TypeOf(mw);
            const info = @typeInfo(T);
            if (info == .pointer and @typeInfo(info.pointer.child) == .@"fn") {
                // function pointer — ok
            } else if (info == .@"fn") {
                // bare function reference — ok
            } else {
                @compileError("Chain: item " ++ std.fmt.comptimePrint("{d}", .{i}) ++ " is not a function or function pointer");
            }
        }
    }

    return struct {
        /// Thread-local storage for the terminal handler.
        /// This is needed because Zig inner functions cannot capture
        /// outer parameters, so we pass the handler through a module-level var.
        /// Set during Chain.run() before handler dispatch; must not be read before then.
        threadlocal var terminal_handler: HandlerFn = undefined;

        /// Run the middleware chain, ending with `handler`.
        /// `io` is passed through to every middleware function.
        /// Fully unrolled at comptime — no runtime dispatch table.
        pub fn run(io: std.Io, req: *Request, res: *Response, handler: HandlerFn) void {
            terminal_handler = handler;
            dispatch(0, io, req, res);
        }

        /// Recursive comptime dispatch: at index i, call middleware[i]
        /// with a comptime-known `next` that dispatches to i+1.
        fn dispatch(comptime idx: comptime_int, io: std.Io, req: *Request, res: *Response) void {
            if (idx >= mws.len) {
                terminal_handler(req, res);
                return;
            }
            const next = struct {
                fn invoke(i: std.Io, r: *Request, s: *Response) void {
                    dispatch(idx + 1, i, r, s);
                }
            }.invoke;
            mws[idx](io, req, res, next);
        }
    };
}

test {
    std.testing.refAllDecls(@This());
}
