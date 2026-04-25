# JDA Forge

A full-stack web framework for the [Jda language](https://github.com/jdalang/jda). Ships as a single `--include` file; everything from routing and ORM to mailer, WebSocket, testing, and background jobs is built in.

---

## Installation

```bash
# Latest
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh

# Specific version
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh -s -- --version v3.0.0
```

Installs to `~/.jda/forge/`, links `forge` CLI to `~/.jda/bin/`.

```bash
forge version          # JDA Forge CLI v3.0.0
forge self-update      # upgrade to latest
```

**Manual install:** clone to `~/.jda/forge`, add `~/.jda/bin` to `$PATH`, symlink `bin/forge`.

---

## Quick Start

```bash
forge new myapp
cd myapp
forge install
cp .env.example .env.development   # set DATABASE_URL and APP_SECRET
forge server                        # build + start on :8080  (alias: forge s)
forge console                       # open database console   (alias: forge c)
```

Minimal app:

```jda
fn handle_root(ctx: i64) {
    ctx_html(ctx, 200, "<h1>Hello from Forge</h1>")
}

fn main() {
    load_env()
    let app = app_new_config(app_config())
    app_use(app, fn_addr(forge_logger))
    app_get(app, "/", fn_addr(handle_root))
    app_listen(app, 8080)
}
```

---

## Example App

[`examples/blog/`](examples/blog/) — complete Posts + Comments CRUD with sessions, CSRF, declarative validations, callbacks, soft delete, multi-environment config, and request tests.

```bash
cd examples/blog
forge install
cp .env.example .env.development
forge server
```

Walkthrough: [docs/blog-example.md](docs/blog-example.md)

---

## What's built in

**Routing** — resources DSL, namespaces, middleware, path helpers, before/after filters.

**ORM** — Rails-style query builder (`where_eq`, `order`, `limit`, `joins`, `group`, `having`, aggregates, scopes, batch processing). Auto-generates typed CRUD functions from migration files.

**Declarative validations** — declare once at startup, fire automatically on every save:

```jda
fn post_validations_init() {
    forge_model("posts")
    forge_field       ("title, body, author", FORGE_V_PRESENCE)
    forge_field_length("title",               2, 255)
    forge_field_min   ("body",                10)
}
```

**Strong parameters** — `ctx_permit(ctx, "title, body, author")` whitelists and extracts form fields.

**Callbacks** — `FORGE_CB_BEFORE_SAVE`, `AFTER_SAVE`, `BEFORE_CREATE`, `AFTER_CREATE`, `BEFORE_UPDATE`, `AFTER_UPDATE`, `BEFORE_DELETE`, `AFTER_DELETE`, `AFTER_COMMIT`, `AFTER_ROLLBACK`.

**Transactions** — `forge_begin/commit/rollback()` or `forge_transaction(fn_ptr)`.

**Controllers** — thin action functions, `ctx_render`, `ctx_redirect`, flash, strong params, format-aware `ctx_respond_to`.

**JSON API** — `ctx_json_ok`, `ctx_json_created`, `ctx_json_errors` (422 with validation body), `forge_result_to_json`, `ForgeJson` builder for selective fields.

**Sessions & CSRF** — cookie sessions, automatic CSRF token generation and validation.

**Security** — bcrypt password hashing (`forge_secure_password_set/verify`), SQL-injection-safe escaping, HTML escaping, secure headers middleware, JWT auth helpers.

**Background jobs** — worker pool, `forge_job_enqueue(fn_addr(job_fn), arg)`.

**Mailer** — SMTP, HTML/text bodies, async delivery.

**WebSocket & SSE** — upgrade, broadcast, Server-Sent Events.

**Migrations** — numbered SQL files, auto-run at startup, tracked in database.

**Testing** — in-process request tests, no sockets, chainable assertions.

**Caching, file uploads, i18n, serializers** — all built in.

---

## CLI

```bash
forge server                                 # build + start dev server  (alias: forge s)
forge server --port 3000                     # custom port
forge server --environment production        # different environment
forge console                                # open database console  (alias: forge c)
forge console --environment staging          # connect to staging DB

forge new <name>                             # scaffold a new project
forge install                                # install deps from Forgefile
forge install --locked                       # exact versions (use in CI)
forge add <lib> [--version v1.2.0]          # add a library
forge update [<lib>]                         # update all or one library
forge list                                   # show installed libraries

forge generate scaffold Post title:string body:text   # model + routes + views + test
forge generate model    Post title:string             # model only
forge generate migration add_slug_to_posts slug:string

forge compile-routes                         # regenerate _build/routes.jda + _build/controllers.jda
forge compile-models                         # regenerate _build/models.jda from db/migrate/

forge release v3.1.0                         # tag + push + GitHub release
forge self-update [--version v3.1.0]         # update the CLI itself
```

---

## Documentation

**Start here:** [Getting Started](docs/getting-started.md) · [Blog Example](docs/blog-example.md)

**Core:** [Routing](docs/routing.md) · [Models](docs/models.md) · [Views](docs/views.md) · [Security](docs/security.md) · [Testing](docs/testing.md) · [Configuration](docs/configuration.md)

**Features:** [Mailer](docs/mailer.md) · [Background Jobs](docs/background-jobs.md) · [WebSocket](docs/websocket.md) · [SSE](docs/sse.md) · [Caching](docs/caching.md) · [File Uploads](docs/file-uploads.md) · [i18n](docs/i18n.md)

**Reference:** [Libraries](docs/libraries.md) · [Overriding](docs/overriding.md)

Full index: [docs/README.md](docs/README.md)
