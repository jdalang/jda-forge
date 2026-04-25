# JDA Forge — Documentation

## Start here

| Guide | Description |
|---|---|
| [getting-started.md](getting-started.md) | Installation, project structure, first app, build pipeline |
| [blog-example.md](blog-example.md) | Full walkthrough of the example app |

## Core

| Guide | Description |
|---|---|
| [generators.md](generators.md) | `forge generate scaffold/model/controller/migration`, field types, `forge db:migrate/rollback/status` |
| [routing.md](routing.md) | Routes, request/response API, middleware, before/after filters |
| [models.md](models.md) | Query builder, declarative validations, callbacks, transactions, associations, multiple databases |
| [serializers.md](serializers.md) | JSON serializers — auto-render, selective fields, computed fields, conditions |
| [views.md](views.md) | HTML helpers, forms, layout, partials, escaping |
| [security.md](security.md) | SQL injection, XSS, CSRF, authentication, bcrypt passwords, secure headers |
| [testing.md](testing.md) | Request tests, assertions, database fixtures |
| [configuration.md](configuration.md) | Environments, .env files, app_config, log levels |

## Features

| Guide | Description |
|---|---|
| [mailer.md](mailer.md) | Sending email (SMTP), async mail, ForgeMail struct |
| [background-jobs.md](background-jobs.md) | Worker pool, job functions, async processing |
| [websocket.md](websocket.md) | WebSocket upgrade, send/receive, broadcast patterns, channels (pub/sub) |
| [sse.md](sse.md) | Server-Sent Events — live feeds, notifications |
| [assets.md](assets.md) | Asset pipeline — CSS/JS fingerprinting, `forge_stylesheet_tag`, `forge_javascript_tag` |
| [caching.md](caching.md) | In-process cache, response caching middleware |
| [file-uploads.md](file-uploads.md) | Multipart parsing, validation, saving uploads |
| [i18n.md](i18n.md) | Locale files, translation, per-request locale |

## Reference

| Guide | Description |
|---|---|
| [advanced.md](advanced.md) | ctx_head, signed cookies, pessimistic locking, enum helpers, current attributes, rescue handler, delayed jobs, backoff retry |
| [libraries.md](libraries.md) | Forgefile, version pinning, Forgefile.lock, writing libraries |
| [overriding.md](overriding.md) | Monkey patching, patch files, middleware override |
