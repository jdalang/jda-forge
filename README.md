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

[`examples/blog/`](examples/blog/) — complete Posts + Comments CRUD with sessions, CSRF, validations, soft delete, multi-environment config, and request tests.

```bash
cd examples/blog
forge install
cp .env.example .env.development
make run
```

Walkthrough: [docs/blog-example.md](docs/blog-example.md)

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

forge generate scaffold Post title:string body:text   # model + routes + test
forge generate model    Post title:string             # model only
forge generate migration add_slug_to_posts slug:string

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
