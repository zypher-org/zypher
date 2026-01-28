# zypher Framework – Router & Path Matching (v1)

> **Status:**  Frozen (v1)
>
> This document defines how HTTP requests are matched to handlers in zypher.
> Once frozen, all HTTP adapters and extensions must obey these semantics.

---

## 1. Router Goals

1. Deterministic routing (no ambiguity)
2. Explicit method-based dispatch
3. Fast path matching (no regex engine)
4. Zero allocations during matching
5. Clear precedence rules

---

## 2. Core Concepts

### Route
A route is a tuple:

```
(Method, PathPattern) → Handler
```

### Router
The router:
- stores routes
- matches incoming requests
- extracts path parameters
- selects exactly **one** handler or returns 404/405

---

## 3. Supported HTTP Methods

zypher v1 supports:

- GET
- POST
- PUT
- PATCH
- DELETE
- OPTIONS
- HEAD

Methods are matched **before** paths.

---

## 4. Path Pattern Syntax (Frozen)

Paths are UTF-8 strings split by `/`.

### Static Segment
```
/users
/posts/latest
```

Matches only identical text.

---

### Named Parameter Segment
```
/users/:id
/posts/:slug
```

Rules:
- `:` prefix defines a parameter
- parameter name is `[a-zA-Z_][a-zA-Z0-9_]*`
- matches exactly one path segment

Example:
```
/users/42 → { id = "42" }
```

---

### Wildcard Segment (Catch-All)
```
/assets/*path
```

Rules:
- `*` matches the remainder of the path
- must be the **last segment**

Example:
```
/assets/js/app.js → { path = "js/app.js" }
```

---

## 5. Invalid Patterns (Rejected at Registration)

- Multiple wildcards in one path
- Wildcard not in last position
- Empty parameter names
- Duplicate parameter names

Router must reject these **at startup**, not runtime.

---

## 6. Matching Precedence Rules (Critical)

Routes are matched in this order:

1. Static segments
2. Named parameters
3. Wildcards

### Example

Registered routes:
```
/users/me
/users/:id
/users/*rest
```

Incoming path:
```
/users/me
```

Matched route:
```
/users/me
```

---

## 7. Path Parameter Storage

During matching, extracted parameters are stored in:

```zig
req.params: StringMap([]const u8)
```

Rules:
- Values are slices into request path (no allocation)
- Lifetime equals request lifetime
- Parameters are immutable

---

## 8. Query vs Path Parameters

| Type | Source | Mutability |
|----|----|----|
| Path params | URL path | immutable |
| Query params | URL query | immutable |

They are stored separately and never merged.

---

## 9. Method Mismatch Handling

If:
- path matches
- but HTTP method does not

Then:
- return **405 Method Not Allowed**
- include `Allow` header with valid methods

---

## 10. Not Found Handling

If no path matches:

- return **404 Not Found**

Router does not generate response bodies — middleware may.

---

## 11. Router API (Conceptual)

```zig
router.get(path, handler);
router.post(path, handler);
router.handle(ctx) !Response;
```

> Exact struct layout is **not frozen yet**, only behavior.

---

## 12. Performance Guarantees

- Matching is O(n) over path segments
- No heap allocations during request handling
- Route registration may allocate

---

## 13. Invariants (Non-Negotiable)

- Exactly one handler per request
- No backtracking
- No regex matching
- No mutation of request during routing

Breaking these requires a **major version bump**.

---

## 14. Status

- Path syntax frozen

- Matching rules frozen

- Precedence rules frozen

- Safe to implement router internals

