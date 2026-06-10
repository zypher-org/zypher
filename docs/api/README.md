# Zypher API Reference

This directory contains the zypher web framework API reference.

Use the Zypher CLI for normal project workflows:

```sh
zig build
export PATH="$PWD/zig-out/bin:$PATH"
zypher new examples/blog --template mvc
zypher run examples/blog
zypher doc
zypher doc-user examples/blog
```

## Core
- App, Request, Response, Server, Method, Cookie, SameSite

## Router
- Route, RouteParams, Router

## Middleware
- Chain, Logger, CORS, CSRF, RateLimit, Static, Compress, Session, SecurityHeaders, Recovery

## Template
- Lexer, Parser, Renderer, Context, TemplateEngine, Filters

## ORM
- SQLite, Schema, Query, Migration

## Forms
- Form, Field, FieldDef, FieldKind, Validators

## Auth
- Session, Password, User

## Admin
- AdminSite, Registration, setDb, setEngine

## CLI
- Runner, RunserverConfig, project templates, API variants, scaffold runner, docs server
