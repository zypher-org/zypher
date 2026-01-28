# zypher v0.1.0 – Release Checklist

> **Release Type:** Initial Developer Preview
>
> **Audience:** Early adopters, contributors, framework hackers
>
> **Goal:** Ship a *correct, spec-compliant foundation* — not a feature-complete framework.

---

## 1. Release Philosophy

zypher v0.1.0 is about **trust**, not breadth.

This release guarantees:
- Stable core APIs
- Predictable behavior
- Spec-compliant execution

It explicitly does **NOT** guarantee:
- High performance
- Async support
- ORM or templating

Those come later.

---

## 2. Mandatory Components (Must Ship)

### 2.1 Core Types

- [ ] `Request` (frozen v1)
- [ ] `Response` (frozen v1)
- [ ] `Context`

---

### 2.2 Execution Model

- [ ] Handler function contract implemented
- [ ] Middleware function contract implemented
- [ ] Middleware composition engine
- [ ] Exactly-once `next()` enforcement

---

### 2.3 Router

- [ ] Route registration
- [ ] Path parsing & validation
- [ ] Static route matching
- [ ] Param route matching
- [ ] Wildcard route matching
- [ ] Precedence rules enforced
- [ ] Method dispatch
- [ ] 404 handling
- [ ] 405 handling with `Allow` header

---

### 2.4 HTTP Adapter (Minimal)

- [ ] std.net-based HTTP server
- [ ] Request parsing → `Request`
- [ ] Response serialization → socket
- [ ] Graceful connection close

> Async support is **explicitly out of scope** for v0.1.0

---

## 3. Testing Requirements

### 3.1 Conformance

- [ ] All Core Conformance Tests pass
- [ ] No skipped tests
- [ ] No flaky tests

---

### 3.2 Memory Safety

- [ ] No allocator leaks
- [ ] All ownership rules respected
- [ ] No undefined behavior

---

### 3.3 CI

- [ ] GitHub Actions green
- [ ] Codeberg / Woodpecker green

---

## 4. Documentation Requirements

- [ ] README up to date
- [ ] CONTRIBUTING.md present
- [ ] Specs referenced clearly
- [ ] Minimal "Getting Started" example

---

## 5. Public API Audit (Critical)

Before tagging v0.1.0:

- [ ] All exported symbols reviewed
- [ ] No accidental exports
- [ ] Naming consistent
- [ ] Frozen APIs unchanged

> Once released, breaking these requires **v0.2.0+**

---

## 6. Example Application

- [ ] Minimal "Hello World" app
- [ ] Demonstrates:
  - middleware
  - routing
  - response building

This example is part of the release contract.

---

## 7. Versioning & Tagging

- [ ] Version set to `0.1.0`
- [ ] Git tag created
- [ ] Release notes written

---

## 8. Release Notes Content

Release notes MUST include:

- What zypher is
- What v0.1.0 includes
- What is explicitly missing
- Stability guarantees
- Roadmap link

No hype. No promises you can’t keep.

---

## 9. Post-Release Rules

After v0.1.0:

- [ ] Bug fixes allowed
- [ ] Performance improvements allowed
- [ ] No breaking API changes
- [ ] New features require v0.2.0

---

## 10. Definition of Done (v0.1.0)

zypher v0.1.0 is **DONE** when:

- All checkboxes above are checked
- Core specs are enforced by tests
- Framework can serve a real HTTP request
- Maintainers are confident in correctness

---

## Final Reminder

A small, correct release beats a big, unstable one.

zypher’s strength is **discipline** — protect it.



