# zypher Framework – Core Conformance Test Specifications (v1)

> **Status:**  Authoritative
>
> This document defines **all mandatory tests** required for zypher v1 compliance.
> Any implementation MUST pass these tests to be considered correct.

---

## 0. Testing Philosophy

- Tests define behavior, not implementation
- Black-box testing where possible
- No reliance on HTTP server internals
- All tests are deterministic
- Memory safety is part of correctness

---

# SECTION A — Request Tests

## A1. Request Immutability

**Given** a constructed Request
**When** passed through handler and middleware
**Then** no field of Request can be mutated

 Attempted mutation must fail at compile-time

---

## A2. Request Path Integrity

**Given** request path `/users/42`
**Then**:
- `req.path == "/users/42"`
- Path slices used for params must point into this buffer

---

## A3. Query Parameters Isolation

**Given** `/search?q=zig&sort=asc`

**Then**:
- `req.query["q"] == "zig"`
- `req.query["sort"] == "asc"`
- `req.params` is empty

---

# SECTION B — Response Tests

## B1. Default Response State

**Given** a new Response
**Then**:
- status = 200
- headers empty
- body empty

---

## B2. Response Mutation

**Given** a Response from handler
**When** middleware modifies headers
**Then** modifications persist

---

## B3. Ownership Rules

**Given** response body
**Then**:
- response owns body memory
- freeing response frees body

---

# SECTION C — Handler Tests

## C1. Handler Return Contract

**Given** a handler
**Then**:
- it must return `Response`
- error propagation is allowed

---

## C2. Handler Purity

**Given** same Context
**Then**:
- handler must produce identical Response

(No hidden global state allowed)

---

# SECTION D — Middleware Tests

## D1. Middleware Order

**Given** middleware A, B and handler H

**Expected execution order**:
```
A (before)
B (before)
H
B (after)
A (after)
```

---

## D2. Short-Circuit Middleware

**Given** middleware returns Response early
**Then**:
- `next()` is NOT called
- handler is NOT executed

---

## D3. Exactly-Once Rule

**Given** middleware
**Then**:
- calling `next()` zero or multiple times is invalid
- implementation MUST prevent or detect this

---

## D4. Request Safety

**Given** middleware
**Then**:
- mutation of `ctx.req` is impossible

---

# SECTION E — Router Registration Tests

## E1. Valid Route Registration

**Given** valid static, param, wildcard routes
**Then**:
- registration succeeds

---

## E2. Invalid Route Rejection

**Given**:
- duplicate param names
- wildcard not last
- multiple wildcards

**Then**:
- router initialization fails

---

# SECTION F — Router Matching Tests

## F1. Static Match

**Route** `/users/me`
**Request** `/users/me`
**Then** handler is selected

---

## F2. Param Match

**Route** `/users/:id`
**Request** `/users/42`
**Then**:
- handler selected
- `params.id == "42"`

---

## F3. Wildcard Match

**Route** `/assets/*path`
**Request** `/assets/js/app.js`
**Then**:
- `params.path == "js/app.js"`

---

## F4. Precedence Rules

**Routes**:
```
/users/me
/users/:id
/users/*rest
```

**Request** `/users/me`

**Then** static route is selected

---

## F5. Method Dispatch

**Given** GET and POST registered on same path
**When** POST request received
**Then** POST handler selected

---

## F6. Method Not Allowed (405)

**Given** path match but method mismatch
**Then**:
- status = 405
- `Allow` header present

---

## F7. Not Found (404)

**Given** no matching route
**Then**:
- router returns NotFound

---

# SECTION G — Integration Tests

## G1. Router + Middleware Integration

**Given** middleware + router + handler
**Then**:
- middleware wraps router correctly
- response flows outward

---

## G2. Error Propagation

**Given** handler throws error
**Then**:
- recover middleware converts to response

---

# SECTION H — Memory & Performance Tests

## H1. No Allocation on Match

**Given** request routing
**Then**:
- no heap allocation during matching

---

## H2. Parameter Slice Lifetime

**Given** path params
**Then**:
- slices valid until request end

---

# SECTION I — Compliance

An implementation is **zypher v1 compliant** if:

- All tests above pass
- No invariants are violated
- No undefined behavior occurs

---

## FINAL STATUS

 - Request spec covered

 - Handler spec covered

 - Middleware spec covered

 - Router spec covered

 - Core behavior fully locked

