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

**ORM** — Rails-style query builder (`where_eq`, `order`, `limit`, `joins`, `group`, `having`, aggregates, scopes, batch processing). Tables with `deleted_at` get automatic soft-delete scoping — `post_all()` excludes deleted rows; `post_with_deleted()` and `post_only_deleted()` opt back in. Auto-generates typed CRUD per table including `post_reload`, `post_toggle`, `post_increment`, `post_decrement`, plus `forge_q_pick`, `forge_q_reorder`, `forge_q_reverse_order`, `forge_q_find_each`.

**Declarative validations** — declare once at startup, fire automatically on every save with full lifecycle (`FORGE_CB_BEFORE_VALIDATION` / `FORGE_CB_AFTER_VALIDATION`). Supports create-only or update-only rules via `forge_field_on_create` / `forge_field_on_update`:

```jda
fn post_validations_init() {
    forge_model("posts")
    forge_field       ("title, body, author", FORGE_V_PRESENCE)
    forge_field_length("title",               2, 255)
    forge_field_min   ("body",                10)
}
```

**Strong parameters** — `ctx_permit(ctx, "title, body, author")` whitelists and extracts form fields.

**Callbacks** — `FORGE_CB_BEFORE_VALIDATION`, `AFTER_VALIDATION`, `BEFORE_SAVE`, `AFTER_SAVE`, `BEFORE_CREATE`, `AFTER_CREATE`, `BEFORE_UPDATE`, `AFTER_UPDATE`, `BEFORE_DELETE`, `AFTER_DELETE`, `AFTER_COMMIT`, `AFTER_ROLLBACK`.

**Transactions** — `forge_begin/commit/rollback()` or `forge_transaction(fn_ptr)`.

**Controllers** — thin action functions, `ctx_render`, `ctx_redirect`, `ctx_redirect_back`, flash (`ctx_flash_now`, `ctx_flash_keep`), strong params, format-aware `ctx_respond_to`. HTTP caching via `ctx_etag`, `ctx_last_modified`, `ctx_stale`.

**Before actions** — `forge_ctrl_before(ctrl, fn_ptr, "show, edit")` and `forge_ctrl_before_except(ctrl, fn_ptr, "index, new")` for Rails-style controller filters.

**JSON API** — `ctx_json_ok`, `ctx_json_created`, `ctx_json_errors` (422 with validation body), `forge_result_to_json`, `ForgeJson` builder for selective fields.

**Sessions & CSRF** — cookie sessions, automatic CSRF token generation and validation.

**Security** — bcrypt password hashing (`forge_secure_password_set/verify`), SQL-injection-safe escaping, HTML escaping, secure headers middleware, JWT auth helpers, `forge_token_generate` (cryptographically random tokens), `forge_token_eq_timing` (constant-time comparison), per-key rate limiting (`forge_rate_limit_key`).

**Background jobs** — worker pool, `forge_job_enqueue(fn_addr(job_fn), arg)`, `forge_job_enqueue_retry(fn_ptr, arg, max_retries)` for automatic retry on failure.

**Mailer** — SMTP, HTML/text bodies, async delivery.

**WebSocket & SSE** — upgrade, broadcast, Server-Sent Events.

**Channels** — Action Cable style pub/sub over WebSocket. Register named channels (`forge_channel_register`), broadcast from anywhere (`forge_channel_broadcast`), and handle the full subscribe/message/unsubscribe lifecycle with typed callbacks.

**Migrations** — numbered SQL files, auto-run at startup, tracked in database.

**Testing** — in-process request tests, no sockets, chainable assertions. `forge_test_fixture` inserts test records, `forge_test_rollback` / `forge_test_setup` wrap each test in a transaction, `forge_test_res_json` asserts JSON response keys.

**View helpers** — `forge_time_ago`, `forge_distance_of_time`, `forge_number_to_currency`, `forge_number_with_delimiter`, `forge_word_wrap` for formatting in templates.

**Caching** — `forge_cache_fetch(key, ttl, fn_ptr)` for memoized caching. File uploads, i18n, serializers all built in.

---

## CLI

```bash
forge server                                 # build + start dev server  (alias: forge s)
forge server --port 3000                     # custom port
forge server --environment production        # different environment
forge console                                # open database console  (alias: forge c)
forge console --environment staging          # connect to staging DB
forge db:migrate                             # run pending migrations
forge db:migrate --environment production    # run migrations on a specific environment
forge db:rollback                            # roll back last migration
forge db:rollback --step 3                   # roll back last 3 migrations
forge db:rollback --version 002              # rollback to version 002
forge db:status                              # show ran vs. pending migrations

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
