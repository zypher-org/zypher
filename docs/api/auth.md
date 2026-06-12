# Auth API

## Session
In-memory session store with 256-bit random session IDs.

### Constants
- `SESSION_ID_LEN = 32` — session ID length in bytes (256-bit)

### CookieConfig
- `httponly: bool = true` — not accessible to JavaScript
- `secure: bool = true` — only sent over HTTPS
- `samesite: [:0]const u8 = "Strict"` — SameSite policy
- `path: [:0]const u8 = "/"` — cookie path
- `max_age: u32 = 86400` — session max age in seconds (24 hours)

### Functions
- `cookieConfig() CookieConfig` — return the default cookie config

### Session
- `id: [SESSION_ID_LEN]u8` — raw session ID bytes
- `data: std.StringHashMap([]const u8)` — session key-value data
- `expires_at: i64` — Unix timestamp when session expires (0 = no expiry)

#### Methods
- `session.put(gpa, key, value) !void` — set session data (deep-copies key and value)
- `session.get(key) ?[]const u8` — get session data
- `session.isExpired() bool` — check if session has expired
- `session.deinit(gpa)` — free session data

### SessionStore
- `SessionStore.init(gpa) SessionStore` — create an in-memory session store
- `store.deinit()` — free all sessions and the store
- `store.create() !Session` — create a new session with random ID and default expiry
- `store.createWithExpiry(expires_at) !Session` — create a session with a specific expiry timestamp
- `store.save(session) !void` — save a session into the store (deep-copies all data)
- `store.getByHexId(hex_id) !?*Session` — load a session by hex-encoded cookie value; returns null if expired
- `store.get(raw_id) !?*Session` — load a session by raw ID bytes
- `store.destroyByHexId(hex_id) !void` — destroy a session by hex-encoded ID
- `store.destroy(raw_id) !void` — destroy a session by raw ID bytes

### Entropy Source
- Linux: `getrandom()` syscall
- BSD/macOS: `arc4random_buf` (when linked with libc)
- Other: returns `error.EntropyUnavailable`

## Password
Password hashing and verification using PBKDF2-HMAC-SHA256.

### Constants
- `HASH_LEN = 32` — hash output length
- `SALT_LEN = 16` — salt length
- `ITERATIONS = 100_000` — PBKDF2 iteration count

### Methods
- `hash(gpa, plaintext) ![]const u8` — hash a password; returns owned string in format `$pbkdf2-sha256$100000$<salt_hex>$<hash_hex>`
- `verify(stored_hash, plaintext) !bool` — verify a password against a stored hash (constant-time comparison)

### PasswordError
- `InvalidHashFormat` — stored hash has unexpected format
- `HashMismatch` — (via timing-safe compare)

## User
User model with hashed password, role, and active status.

### Fields
- `username: []const u8` — owned username
- `password_hash: []const u8` — owned PBKDF2 hash
- `role: []const u8 = "user"` — user role string (e.g. "user", "admin")
- `is_active: bool = true` — whether the account is active
- `gpa: std.mem.Allocator` — allocator for owned fields

### Methods
- `User.init(gpa, username, plaintext) !User` — create a user with hashed password
- `user.deinit()` — free user resources
- `user.authenticate(plaintext) !bool` — verify password; returns false if inactive
- `user.setRole(role)` — set the user's role (deep-copies)
- `user.deactivate()` — mark the user inactive

### Auth Middleware Functions
- `loginRequired(req, res, next)` — middleware that requires an authenticated user; redirects to `/login` with 302 if `req.user` is null
- `superuserRequired(req, res, next)` — middleware that requires a user with role `"admin"`; returns 403 if not admin

### Built-in Views
- `loginView(req, res)` — GET renders a login form with CSRF token; POST processes login
- `logoutView(req, res)` — destroys session cookie and redirects to `/`
- `registerView(req, res)` — GET renders a registration form with CSRF token; POST processes registration

## Full Example
```zig
const zypher = @import("zypher");

// Create a session store
var store = zypher.SessionStore.init(gpa);
defer store.deinit();

// Create a session
var session = try store.create();
defer session.deinit(gpa);

// Store data
try session.put(gpa, "username", "alice");
try session.put(gpa, "role", "admin");

// Save to store
try store.save(&session);

// Hash a password
const hash_str = try zypher.hash(gpa, "my_secret_password");
defer gpa.free(hash_str);

// Verify
const valid = try zypher.verify(hash_str, "my_secret_password");

// Create a User
var user = try zypher.User.init(gpa, "alice", "password123");
defer user.deinit();
try user.setRole("admin");
```
