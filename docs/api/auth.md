# Auth API

## Session
- `SessionStore.init(gpa)` — Create an in-memory session store
- `store.create()` — Create a session with the default expiry
- `store.createWithExpiry(expires_at)` — Create a session with a specific expiry
- `store.save(session)` — Save a session into the store
- `store.getByHexId(hex_id)` — Load a session by cookie value
- `store.destroyByHexId(hex_id)` — Destroy a session by cookie value
- `session.put(gpa, key, value)` — Set session data
- `session.get(key)` — Get session data
- `session.isExpired()` — Check expiry

## Password
- `hash(gpa, password)` — Hash a password with PBKDF2-HMAC-SHA256 and an OS-random salt
- `verify(stored_hash, password)` — Verify a password against a stored hash

## User
- `User` fields: `username`, `password_hash`, `role`, `is_active`
- `User.init(gpa, username, plaintext)` — Create a user with a hashed password
- `user.authenticate(plaintext)` — Verify a plaintext password
- `user.setRole(role)` — Set the user's role
- `user.deactivate()` — Mark the user inactive
- `loginRequired(req, res, next)` — Redirect unauthenticated requests to `/login`
- `superuserRequired(req, res, next)` — Require an attached `User` with role `admin`
- Built-in `loginView`, `logoutView`, and `registerView` are minimal handlers; scaffolded apps provide the full admin login flow.
