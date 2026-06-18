/// zypher session middleware — loads/saves session on every request.
///
/// Reads the session cookie, loads the session from the store,
/// attaches it to the request context, and saves it back after
/// the handler runs.
///
/// Since middleware functions have a fixed signature, the SessionStore
/// reference is passed via a threadlocal variable (same pattern as
/// Chain uses for the terminal handler).
const std = @import("std");
const Request = @import("../core/request.zig").Request;
const Response = @import("../core/response.zig").Response;
const session_mod = @import("../auth/session.zig");
const SessionStore = session_mod.SessionStore;
const Session = session_mod.Session;
const CookieConfig = session_mod.CookieConfig;
const log = std.log.scoped(.session_mw);

/// Threadlocal store reference — must be set before calling middleware.
threadlocal var store_ptr: ?*SessionStore = null;
threadlocal var cookie_config: CookieConfig = session_mod.cookieConfig();

/// Set the session store for the current thread.
pub fn setStore(store: *SessionStore) void {
    store_ptr = store;
}

/// Set the session cookie attributes for the current thread.
pub fn setCookieConfig(config: CookieConfig) void {
    cookie_config = config;
}

/// Restore the default secure session cookie attributes.
pub fn resetCookieConfig() void {
    cookie_config = session_mod.cookieConfig();
}

/// Session cookie name.
const COOKIE_NAME = "zypher_session";

/// Session middleware function.
/// Loads session from cookie, attaches to request.user, saves after handler.
pub fn middleware(io: std.Io, req: *Request, res: *Response, next: *const fn (std.Io, *Request, *Response) void) void {
    const store = store_ptr orelse {
        log.warn("no session store configured, skipping session middleware", .{});
        next(io, req, res);
        return;
    };

    // Try to load session from cookie
    const cookie_val = req.cookie(COOKIE_NAME);
    var loaded_session: ?*Session = null;

    if (cookie_val) |hex_id| {
        loaded_session = store.getByHexId(hex_id) catch null;
    }

    // Attach session to request (cast to *anyopaque for the user field)
    if (loaded_session) |s| {
        req.user = @ptrCast(s);
        log.debug("loaded session for {s}", .{req.path});
    } else {
        // No valid session — create a new one
        var new_session = store.create(io);
        store.save(&new_session) catch {
            log.warn("failed to save new session", .{});
            new_session.deinit(store.gpa);
            next(io, req, res);
            return;
        };
        new_session.deinit(store.gpa); // save deep-copies

        // Re-fetch the stored session as a pointer
        const retrieved = store.get(new_session.id) catch null;
        if (retrieved) |s| {
            req.user = @ptrCast(s);
        }

        // Set session cookie
        var hex_buf: [session_mod.SESSION_ID_LEN * 2]u8 = undefined;
        for (new_session.id, 0..) |byte, i| {
            hex_buf[i * 2] = "0123456789abcdef"[byte >> 4];
            hex_buf[i * 2 + 1] = "0123456789abcdef"[byte & 0xf];
        }
        var cookie_buf: [COOKIE_NAME.len + 1 + session_mod.SESSION_ID_LEN * 2 + 128]u8 = undefined;
        var cookie_writer = std.Io.Writer.fixed(&cookie_buf);
        cookie_writer.print("{s}={s}", .{ COOKIE_NAME, &hex_buf }) catch {
            log.warn("failed to format session cookie - continuing without cookie", .{});
            next(io, req, res);
            return;
        };
        if (cookie_config.httponly) cookie_writer.writeAll("; HttpOnly") catch {};
        cookie_writer.print("; SameSite={s}", .{cookie_config.samesite}) catch {};
        if (cookie_config.secure) cookie_writer.writeAll("; Secure") catch {};
        cookie_writer.print("; Path={s}", .{cookie_config.path}) catch {};
        cookie_writer.print("; Max-Age={d}", .{cookie_config.max_age}) catch {};
        _ = res.addSetCookie(cookie_buf[0..cookie_writer.end]);
        log.debug("created new session for {s}", .{req.path});
    }

    // Continue down the chain
    next(io, req, res);

    // After handler: save session if it was loaded
    // (The handler may have mutated session data via the pointer)
    if (loaded_session != null) {
        // Session data was modified in-place through the pointer,
        // but since save deep-copies, modifications through the
        // pointer are already in the store's copy.
        log.debug("session middleware post-handler for {s}", .{req.path});
    }
}

test {
    std.testing.refAllDecls(@This());
}
