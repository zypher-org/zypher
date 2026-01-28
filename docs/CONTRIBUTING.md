# Contributing to zypher

First off — **thank you** for your interest in contributing to zypher 

zypher is a **spec-driven, correctness-first web framework written in Zig**. Contributions are welcome, but they must follow the architectural discipline laid out below.

---

## 1. Project Philosophy

zypher is built on a few non-negotiable principles:

- **Specification before implementation**
- **Explicit behavior over magic**
- **Determinism over convenience**
- **Correctness before performance tweaks**

If you enjoy building systems that are easy to reason about under pressure, you’re in the right place.

---

## 2. Read This First (Mandatory)

Before writing any code, contributors **MUST** read and understand:

- Request / Response API (v1)
- Handler & Middleware API (v1)
- Router & Path Matching Specification (v1)
- Core Conformance Test Specifications (v1)

These documents define **authoritative behavior**.

> If code and spec disagree, the **spec wins**.

---

## 3. Frozen APIs (Very Important)

The following are **frozen for zypher v1**:

- Request
- Response
- Context
- HandlerFn
- MiddlewareFn
- Routing semantics
- Path matching rules

###  What this means

-  No renaming exported symbols
-  No adding fields to frozen structs
-  No changing function signatures

Breaking changes require:
- a version bump
- updated specs
- explicit maintainer approval

---

## 4. What You Can Safely Work On

Contributors are encouraged to work on:

- Router implementation (must pass all routing tests)
- Middleware composition engine
- HTTP server adapters
- CLI tooling
- Documentation improvements
- Benchmarks (after correctness)

If unsure, open an issue **before** coding.

---

## 5. Testing Requirements

All contributions **must**:

- Add or update tests
- Pass all conformance tests
- Avoid flaky or timing-dependent tests

### Test philosophy

- Tests describe *behavior*, not internals
- Prefer black-box tests
- Avoid mocks unless unavoidable

---

## 6. Memory & Safety Rules

Because zypher is written in Zig:

- All allocations must be explicit
- Allocator ownership must be clear
- No hidden global state
- No thread-local storage
- No undefined behavior tolerated

Memory safety regressions are treated as **critical bugs**.

---

## 7. Error Handling Guidelines

- Errors are part of the API
- Do not swallow errors silently
- Let middleware decide recovery strategy

Panics should only be used for **programmer errors**, not runtime conditions.

---

## 8. Code Style

- Follow `zig fmt`
- Prefer small, composable functions
- Avoid cleverness
- Optimize only with evidence

Readable code beats short code.

---

## 9. Commit & PR Guidelines

### Commits

- Use clear, descriptive messages
- One logical change per commit

### Pull Requests

- Explain *why* the change exists
- Reference relevant spec sections
- Mention tests added or updated

PRs that break specs will be rejected, even if they "work".

---

## 10. How Decisions Are Made

zypher follows a **maintainer-led, spec-driven** model:

- Specs are discussed openly
- Once frozen, specs are enforced strictly
- Implementation details remain flexible

This avoids churn and long-term instability.

---

## 11. Asking for Help

If you’re unsure about:

- architectural direction
- spec interpretation
- performance implications

Open an issue or start a discussion — questions are welcome.

---

## 12. Final Note

zypher is not trying to be everything to everyone.

It aims to be:
- predictable
- explicit
- boring in the best possible way

If that excites you — we’d love your contribution 

---

**Happy hacking,**  
*The zypher Maintainers*