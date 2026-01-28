
# ISSUE BREAKDOWN (INITIAL BACKLOG)

Issues are grouped by milestone and intentionally small.

---

## Milestone 1 — Core HTTP & Primitives

- [ ] Setup base project structure
- [ ] Integrate `std.http.Server`
- [ ] Implement `Request` struct
- [ ] Implement `Response` struct
- [ ] Add response helpers (`text`, `json`, `redirect`)
- [ ] Write basic HTTP tests

---

## Milestone 2 — Routing & Middleware

- [ ] Router v1: static path matching
- [ ] Router v2: typed URL parameters
- [ ] Compile-time route validation
- [ ] Middleware interface design
- [ ] Middleware execution pipeline
- [ ] Built-in logger middleware

---

## Milestone 3 — Views & Templates

- [ ] Controller API definition
- [ ] View helpers (`render`, `redirect`)
- [ ] Template tokenizer
- [ ] Template parser (AST)
- [ ] Template renderer
- [ ] HTML auto-escaping

---

## Milestone 4 — ORM & Migrations

- [ ] SQLite integration
- [ ] Model definition macro/API
- [ ] Compile-time SQL generation
- [ ] CRUD operations
- [ ] Migration file format
- [ ] Migration runner

---

## Milestone 5 — Forms, Auth & Sessions

- [ ] Form struct definitions
- [ ] Validation rules
- [ ] Error aggregation
- [ ] CSRF protection
- [ ] Session storage (signed cookies)
- [ ] Password hashing (argon2)

---

## Milestone 6 — Admin, CLI & Docs

- [ ] CLI command parser
- [ ] `zypher new` project generator
- [ ] `zypher run` server command
- [ ] Admin CRUD UI generator
- [ ] Permissions integration
- [ ] Example blog project
- [ ] Documentation pass

---

# Issue Management Rules

- One concern per issue
- No issue longer than ~2 days of work
- Architectural changes require discussion
- Performance tuning only after correctness

---

# Final Note

zypher is a long-form engineering project.

Progress is measured not by speed, but by:
- Clarity of design
- Quality of abstractions
- Ease of understanding

If the framework remains understandable at the end, the project has succeeded.
