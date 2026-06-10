# Auth API

## Session
- `session.init() Session` — Create a new session
- `session.set(key, value)` — Set session data
- `session.get(key)` — Get session data
- `session.destroy()` — Destroy the session

## Password
- `hash(gpa, password)` — Hash a password (bcrypt-style)
- `verify(password, hash)` — Verify a password against a hash

## User
- `User` struct with field definitions for authentication
- Compatible with ORM schema system
