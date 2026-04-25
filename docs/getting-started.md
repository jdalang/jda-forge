# Getting Started with JDA Forge

JDA Forge is a web framework for the Jda language. Jda compiles to native x86-64 binaries, calls the kernel directly (no libc), and manages memory without a garbage collector. Forge brings database access, HTTP routing, sessions, CSRF protection, and migrations to that environment — without changing what Jda is.

This guide walks from zero to a running application with your first custom handler, a generated resource, and a passing test suite.

---

## Table of Contents

1. [Concepts to know](#concepts-to-know)
2. [Prerequisites](#prerequisites)
3. [Installing Forge](#installing-forge)
4. [Creating a new project](#creating-a-new-project)
5. [Project structure](#project-structure)
6. [First run](#first-run)
7. [The build pipeline](#the-build-pipeline)
8. [Generating your first resource](#generating-your-first-resource)
9. [Writing a handler manually](#writing-a-handler-manually)
10. [Running tests](#running-tests)
11. [Next steps](#next-steps)

---

## Concepts to know

Three ideas come up constantly when working with Forge. Understanding them upfront saves a lot of head-scratching.

### Single-file compilation model

Jda compiles one source file. Forge works around this by having your Makefile concatenate all your `.jda` files into `_build/app.jda` before invoking the compiler. The file order is deliberate: `config/application.jda` goes first (it defines constants and `load_env`), then helpers, models, views, controllers, and finally `main.jda`. Libraries arrive via `--include` flags, which are processed before your app source.

The upshot: **every function in your project is global**. There are no modules, no namespacing, no import statements. By convention, name your functions with a prefix that reflects where they live — `post_create`, `view_posts_index`, `posts_index`.

### UFCS — Uniform Function Call Syntax

Jda supports method-style chaining on any value. `post_q().where_eq("published", "true").order_desc("created_at").exec()` is valid even though `post_q()` returns a plain `&ForgeQuery` pointer and there are no classes. Each call in the chain is just a function that takes its left-hand side as the first argument. You can chain off anything — it is syntax sugar, not object orientation.

### No GC — explicit allocation, no hidden cost

Jda has no garbage collector. Memory is allocated with `alloc_pages(n)`, which gives you `n * 4096` bytes of heap. Forge manages per-request arenas for you (the context allocator), so inside a handler you rarely call `alloc_pages` directly. For building HTML responses from many parts, use `ForgeBuf`:

```jda
let buf = forge_buf_new(8)   // 32 KiB buffer
buf.write("<h1>").write(h(title)).write("</h1>")
ctx_html(ctx, 200, buf.done())
```

`forge_buf_write` returns `&ForgeBuf` so calls chain. `forge_buf_done` returns the accumulated `[]i8` slice. The benefit of no GC is predictable latency: no pauses, no stop-the-world events, no surprises under load.

---

## Prerequisites

Before installing Forge you need:

**Jda compiler** — the `jda` binary must be on your `PATH`. Download the latest release from [github.com/jdalang/jda](https://github.com/jdalang/jda/releases) and move it somewhere in your path:

```bash
# example — adjust version and platform
curl -L https://github.com/jdalang/jda/releases/download/v0.9.0/jda-linux-x86_64.tar.gz | tar xz
sudo mv jda /usr/local/bin/
jda --version
```

**PostgreSQL 14+** — Forge's database layer targets PostgreSQL. A local install or a Docker container both work:

```bash
# Docker — quick local database
docker run -d \
  --name pgdev \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:16-alpine

# Verify connectivity
psql postgres://postgres:postgres@localhost:5432/postgres -c '\l'
```

**GNU Make** — the generated `Makefile` uses standard `make` syntax. It ships with most Linux distributions and with Xcode Command Line Tools on macOS.

**entr** (optional) — used by `forge server --watch` for live reload. Install with your system package manager (`brew install entr`, `apt install entr`, etc.).

---

## Installing Forge

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh
```

This places the `forge` binary in `~/.local/bin`. Add that directory to your `PATH` if it is not already there:

```bash
# add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
```

### Installing a specific version

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh -s -- --version v3.0.0
```

### Verifying the install

```bash
forge version
# JDA Forge CLI v3.0.0
```

### Upgrading

Run the one-line install again. It overwrites the existing binary in place.

---

## Creating a new project

```bash
forge new myapp
cd myapp
```

`forge new` scaffolds a complete project in the `myapp/` directory:

```
myapp/
  Forgefile             # dependency manifest — lists forge and libraries
  Forgefile.lock        # exact resolved SHAs — commit this file
  Makefile              # build pipeline
  main.jda              # middleware registration, routes, server start
  .env                  # FORGE_ENV=development (shared defaults, commit it)
  .env.example          # template for per-environment secrets
  .gitignore
  app/
    controllers/        # one file per resource: posts_controller.jda
    models/             # one file per resource: post.jda
    views/
      layouts/          # application.html.jda
      posts/            # index, show, new, edit views + partials
      shared/           # _errors.html.jda and other cross-resource partials
    helpers/            # application_helper.jda
  config/
    application.jda     # load_env() and app_config()
    routes.jda          # path helpers + routes() function
    environments/       # development.jda, test.jda, production.jda
  db/
    migrate/            # numbered .sql files: 001_create_posts.sql
    seeds.jda           # seed data
  test/                 # request-level tests: test_posts.jda
  public/               # static assets
  libs/                 # installed libraries (gitignored except forge.jda)
```

### File-by-file

**`Forgefile`** declares dependencies, similar to a Gemfile or package.json:

```
forge "github.com/jdalang/jda-forge" version "3.0.0"
```

Additional libraries are added with `lib` lines. See [libraries.md](libraries.md) for the full format.

**`Forgefile.lock`** records the exact git SHA for every dependency after `forge install` resolves them. Commit this file. It ensures every developer and every CI run installs identical code.

**`Makefile`** is the internal build pipeline. You never run `make` directly — `forge server`, `forge build`, and `forge test` call into it for you. It uses GNU Make's `find` to pick up new `.jda` files automatically — you do not need to edit it when you add a model, controller, or view file.

**`config/application.jda`** defines two functions that `main.jda` calls first:
- `load_env()` — reads `.env` then the environment-specific file (`.env.development`, `.env.production`, etc.) based on `$FORGE_ENV`.
- `app_config()` — reads environment variables into a `ForgeConfig` struct and sets the log level.

**`config/routes.jda`** is the routes DSL you edit — declare resources, namespaces, scopes, and custom routes here. `forge build` compiles it into `_build/routes.jda` (path helpers + `routes()` function) and auto-generates `_build/controllers.jda` by scanning your controllers. You never edit the `_build/` files.

**`main.jda`** is the entry point. It calls `load_env`, creates the app, registers middleware, calls model validation init functions (e.g. `post_validations_init()`), calls `routes(app)`, runs migrations, and starts listening.

**`.env`** holds defaults that are safe to commit — typically just `FORGE_ENV=development` and `APP_PORT=8080`. Per-environment files (`.env.development`, `.env.production`) hold secrets and are gitignored.

---

## Project structure

Here is where each kind of code lives and why.

| Directory / file | What goes here |
|---|---|
| `config/application.jda` | `load_env()`, `app_config()`, app-wide constants |
| `config/routes.jda` | Routes DSL — resources, namespaces, custom routes. Compiled to `_build/` on every build |
| `app/models/` | One file per resource: `post.jda` — query functions, validations, create/update/delete |
| `app/views/<resource>/` | One file per action: `index.html.jda`, `show.html.jda`, `new.html.jda`, `edit.html.jda` |
| `app/views/layouts/` | `application.html.jda` — page layout and flash rendering |
| `app/views/shared/` | Cross-resource partials: `_errors.html.jda` |
| `app/controllers/` | One file per resource: `posts_controller.jda` — thin action functions |
| `app/helpers/` | `application_helper.jda` — `h()`, `link_to()`, `pluralize()` |
| `test/` | One file per resource: `test_posts.jda` — chainable request tests |
| `db/migrate/` | Numbered SQL files: `001_create_posts.sql`, `002_create_comments.sql`, … |
| `libs/` | Installed libraries (managed by `forge install`, mostly gitignored) |
| `patches/` | Optional — overrides for library functions (see [overriding.md](overriding.md)) |
| `main.jda` | Wires everything together — always the last file compiled |

**Naming conventions** — Forge enforces Rails-style conventions and raises an error if they are violated:

| Layer | File | Functions |
|---|---|---|
| Model | `app/models/post.jda` | `post_find`, `post_all`, `post_create`, `post_validations_init` |
| Controller | `app/controllers/posts_controller.jda` | `posts_index`, `posts_show`, `posts_create`, … |
| View | `app/views/posts/index.html.jda` | `view_posts_index` |
| Helper | `app/helpers/application_helper.jda` | `h`, `link_to`, `pluralize` |

Resource names must be PascalCase (`Post`, `BlogPost`) — `forge generate scaffold post` is an error.

---

## First run

### 1. Install dependencies

```bash
forge install
```

This fetches `forge.jda` (and any other libraries in your `Forgefile`) into `libs/` and writes `Forgefile.lock`.

### 2. Configure your environment

```bash
cp .env.example .env.development
```

Open `.env.development` and set at minimum:

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/myapp_development
APP_SECRET=replace-with-a-long-random-string
APP_PORT=8080
```

Create the database:

```bash
createdb myapp_development
# or: psql postgres://... -c 'CREATE DATABASE myapp_development'
```

### 3. Start the server

```bash
forge server
```

`forge server` concatenates all source files, compiles, and starts the app. The Makefile is the internal build pipeline — you never run `make` directly.

Forge runs migrations automatically on startup (`forge_migration_run("db/migrate")`), so your tables are created on first launch.

Visit `http://localhost:8080` in a browser. You should get a 404 — that is correct; no routes are registered yet.

### 4. Live reload (optional)

```bash
forge server --watch
```

This uses `entr` to recompile and restart the server whenever any source file changes.

---

## Development workflow

Jda compiles everything — models, controllers, views, routes — into a single native binary. There is no hot-reload layer. Any file change requires a recompile and server restart.

The recommended dev command is:

```bash
forge server --watch
```

Save a file → the binary recompiles → server restarts automatically. You just wait a few seconds.

Compare to Rails:

| Change | Rails | Forge |
|---|---|---|
| Controller / model | Auto-reloads, no restart | Recompile + restart |
| View | Auto-reloads | Recompile + restart |
| `config/routes.jda` | Server restart | Recompile + restart |

The compile step is the tradeoff for a fast, GC-free production binary with no runtime dependencies. For dev-heavy iteration, `forge server --watch` makes the loop automatic.

---

## The build pipeline

Understanding the build pipeline prevents a whole class of confusing compiler errors.

### Why concatenation?

Jda compiles a single file. To support a multi-file project, the Makefile concatenates everything into one file before the compiler sees it. This is explicit and transparent — you can inspect `_build/app.jda` at any time to see exactly what the compiler received.

### Commands

```bash
forge server          # concatenate → compile → run
forge server --watch  # same, restarts on .jda file changes (requires entr)
forge build           # concatenate → compile only
forge test            # concatenate test sources → compile → run test_runner
```

The Makefile is the build engine behind these commands. You never invoke `make` directly. Here is what it does internally:

```makefile
CONFIG      = config/application.jda
HELPERS     = $(shell find app/helpers     -name "*.jda"      2>/dev/null | sort)
MODELS      = $(shell find app/models      -name "*.jda"      2>/dev/null | sort)
VIEWS       = $(shell find app/views       -name "*.html.jda" 2>/dev/null | sort)
CONTROLLERS = $(shell find app/controllers -name "*.jda"      2>/dev/null | sort)
ROUTES      = _build/routes.jda       # generated from config/routes.jda
CTRL_INIT   = _build/controllers.jda  # generated by scanning app/controllers/
MAIN        = main.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS) $(VIEWS) $(CONTROLLERS) $(CTRL_INIT) $(ROUTES) $(MAIN)

_gen:
    @forge compile-routes   # compiles config/routes.jda + scans controllers

build: _gen $(OUT)
    jda build --include libs/forge.jda $(OUT) -o app

test: _gen
    cat $(SRC) > _build/test.jda
    jda build --include libs/forge.jda _build/test.jda -o test_runner
    FORGE_ENV=test ./test_runner
```

### Order rules

The order of `$(SRC)` is not arbitrary:

| Position | File(s) | Why |
|---|---|---|
| First | `config/application.jda` | Defines `load_env`, `app_config`, and constants everything else uses |
| Second | `app/helpers/*.jda` | Defines `h()`, `link_to()`, `pluralize()` that views and controllers call |
| Third | `app/models/*.jda` | Defines types and query functions that controllers and views call |
| Fourth | `app/views/**/*.html.jda` | Defines view functions that controllers call |
| Fifth | `app/controllers/*.jda` | Defines action functions registered as route handlers |
| Sixth | `config/routes.jda` | Routes DSL you write — compiled to `_build/routes.jda` (path helpers + `routes(app)`) before every build |
| Last | `main.jda` | Calls `routes(app)` and all middleware — must see all of the above |

The `--include libs/forge.jda` flag makes Forge's definitions available to your entire app. Because `--include` files are processed before the app source, you can shadow any library function by defining it in your own code (see [overriding.md](overriding.md)).

### Libraries beyond forge.jda

If you install additional libraries (e.g. `forge-markdown`), the Makefile discovers them automatically:

```makefile
FORGE = libs/forge.jda
LIBS  = $(filter-out $(FORGE), $(wildcard libs/*.jda))
LINCS = $(addprefix --include ,$(LIBS))

build: $(OUT)
	jda build --include $(FORGE) $(LINCS) $(OUT) -o $(APP)
```

---

## Generating your first resource

The scaffold generator creates a complete vertical slice — migration, model, routes, and tests — from a single command.

```bash
forge generate scaffold Post title:string body:text author:string
```

This creates:

```
db/migrate/001_create_posts.sql          # CREATE TABLE posts (...)
app/models/post.jda                      # post_find, post_all, post_create, post_update,
                                         # post_delete, post_validations_init
app/controllers/posts_controller.jda     # 7 thin action functions
app/views/posts/index.html.jda           # view_posts_index
app/views/posts/show.html.jda            # view_posts_show
app/views/posts/new.html.jda             # view_posts_new
app/views/posts/edit.html.jda            # view_posts_edit
test/test_posts.jda                      # request tests for each handler
```

It appends `resources "posts"` to `config/routes.jda` automatically. The next `forge build` (or `forge server`) auto-generates the rest — no manual wiring needed.

`config/routes.jda` after scaffolding:

```
root "pages#home"

resources "posts"
```

That is the entire file. `forge build` compiles this into path helpers and a `routes()` function, and scans `app/controllers/posts_controller.jda` to register the action handlers.

Run `forge server`. The full CRUD interface for posts is now live:

| Method | Path | Action |
|---|---|---|
| GET | `/posts` | List all posts |
| GET | `/posts/new` | New post form |
| POST | `/posts` | Create a post |
| GET | `/posts/:id` | Show a post |
| GET | `/posts/:id/edit` | Edit form |
| POST | `/posts/:id` | Update a post |
| DELETE | `/posts/:id` | Delete a post |

### What the generated model looks like

`forge generate scaffold Post title:string body:text author:string` creates two files:

**`db/migrate/001_create_posts.sql`** — the schema. Runs automatically on `forge server`.

**`app/models/post.jda`** — only what you write: validations and custom scopes.

```jda
// app/models/post.jda

fn post_validations_init() {
    forge_model("posts")
    forge_field       ("title, body, author", FORGE_V_PRESENCE)
    forge_field_length("title",               2, 255)
    forge_field_min   ("body",                10)
}

fn post_published() -> &ForgeResult {
    ret forge_q("posts").where_eq("published", "true").order_desc("created_at").exec()
}
```

Validations are declared once at startup (call `post_validations_init()` in `main.jda`) and fire automatically before every insert and update. That's the entire model file.

Every time you run `forge build`, Forge reads the migration and emits `_build/models.jda` automatically:

```jda
// _build/models.jda  — auto-generated, do not edit

// Soft-delete scoped finders (posts has a deleted_at column)
fn post_q()           -> &ForgeQuery  { ret forge_q_where_not_deleted(forge_q("posts")) }
fn post_all()         -> &ForgeResult { ret forge_q_where_not_deleted(forge_q("posts")).order_desc("created_at").exec() }
fn post_find(id)      -> &ForgeResult { ret forge_q_where_not_deleted(forge_q("posts")).where_eq("id", id).first() }
fn post_find_by(col, val) -> &ForgeResult { ret forge_q_where_not_deleted(forge_q("posts")).where_eq(col, val).first() }
fn post_where(col, val)   -> &ForgeQuery  { ret forge_q_where_not_deleted(forge_q("posts")).where_eq(col, val) }
fn post_count()       -> i64  { ret forge_q_where_not_deleted(forge_q("posts")).count() }
fn post_exists(id)    -> bool { ret forge_q_where_not_deleted(forge_q("posts")).where_eq("id", id).exists() }
fn post_with_deleted()  -> &ForgeQuery { ret forge_q_with_deleted(forge_q("posts")) }
fn post_only_deleted()  -> &ForgeQuery { ret forge_q_only_deleted(forge_q("posts")) }

// Mutations
fn post_delete(id)              -> bool { ret forge_soft_delete("posts", id) }
fn post_destroy(id)             -> bool { ret forge_hard_delete("posts", id) }
fn post_touch(id)               -> bool { ret forge_touch("posts", id) }
fn post_update_column(id, col, val) -> bool { ret forge_update_column("posts", id, col, val) }
fn post_find_or_create_by(col, val) -> &ForgeResult { ret forge_find_or_create_by("posts", col, val) }
fn post_reload(id)              -> &ForgeResult { ret forge_reload("posts", id) }
fn post_toggle(id, col)         -> bool { ret forge_toggle("posts", id, col) }
fn post_increment(id, col, by)  -> bool { ret forge_increment("posts", id, col, by) }
fn post_decrement(id, col, by)  -> bool { ret forge_decrement("posts", id, col, by) }

// Typed create/update
fn post_create(title: []i8, body: []i8, author: []i8) -> bool {
    ret forge_attrs_new()
        .set("title",  title)
        .set("body",   body)
        .set("author", author)
        .insert("posts")
}
fn post_update(id: []i8, title: []i8, body: []i8, author: []i8) -> bool {
    ret forge_attrs_new()
        .set("title",  title)
        .set("body",   body)
        .set("author", author)
        .update("posts", id)
}
fn post_create_from(attrs: &ForgeAttrs) -> bool { ret forge_attrs_insert(attrs, "posts") }
fn post_update_from(id: []i8, attrs: &ForgeAttrs) -> bool { ret forge_attrs_update(attrs, "posts", id) }
```

You never write or touch this file.

`post_q()` and the other generated finders automatically exclude soft-deleted rows. To include them, use the generated escape hatches:

```jda
// All non-deleted posts (default)
let res = post_q().where_ilike("title", "%jda%").order_desc("created_at").page(2, 20).exec()

// Include deleted rows
let res = post_with_deleted().order_desc("deleted_at").exec()

// Only deleted rows
let res = post_only_deleted().exec()
```

---

## Writing a handler manually

Sometimes you want a route that does not fit the CRUD scaffold — an API endpoint, a search page, a webhook receiver. Here is how to build one from scratch.

### Step 1 — create the controller

```jda
// app/controllers/hello_controller.jda

fn hello_index(ctx: i64) {
    let name = ctx_query(ctx, "name")
    if name.len == 0 { name = "World" }
    ctx_html(ctx, 200, "<h1>Hello, " + h(name) + "</h1>")
}
```

### Step 2 — add it to config/routes.jda

```
get "/hello" "hello#index"
```

That's it. `forge server` (or `forge server --watch`) recompiles and the route is live.

Visit `http://localhost:8080/hello?name=Alice` — you get `Hello, Alice`.

### Reading request data

| Function | What it reads |
|---|---|
| `ctx_query(ctx, "key")` | URL query parameter: `/path?key=val` |
| `ctx_form(ctx, "key")` | Form body field (application/x-www-form-urlencoded) |
| `ctx_param(ctx, "key")` | Route parameter: `/posts/:id` → `ctx_param(ctx, "id")` |
| `ctx_header(ctx, "name")` | Request header |
| `ctx_body(ctx)` | Raw request body as `[]i8` |
| `ctx_ip(ctx)` | Client IP address |

All of these return `[]i8` (a byte slice). An empty slice (`.len == 0`) means the key was not present.

### Sending responses

| Function | What it sends |
|---|---|
| `ctx_html(ctx, status, body)` | HTML response |
| `ctx_render(ctx, body)` | HTML 200 (shorthand for `ctx_html(ctx, 200, body)`) |
| `ctx_json(ctx, status, body)` | JSON response (`Content-Type: application/json`) |
| `ctx_json_ok(ctx, json)` | JSON 200 |
| `ctx_json_created(ctx, json)` | JSON 201 |
| `ctx_json_errors(ctx)` | JSON 422 with `forge_last_errors()` body |
| `ctx_text(ctx, status, body)` | Plain text response |
| `ctx_redirect(ctx, path)` | 302 redirect |
| `ctx_not_found(ctx)` | 404 response |
| `ctx_too_many_requests(ctx)` | 429 response |
| `ctx_set_header(ctx, name, val)` | Set a response header before sending |
| `ctx_respond_to(ctx, html_fn, json_fn)` | Branch on Accept header — call html_fn or json_fn |

### A JSON API endpoint

Render all columns of a result set in one call:

```jda
fn api_posts_index(ctx: i64) {
    ctx_json_ok(ctx, forge_result_to_json(post_all()))
}

fn api_post_show(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    if post.count == 0 { ctx_not_found(ctx)  ret }
    ctx_json_ok(ctx, forge_row_to_json(post, 0))
}

fn api_posts_create(ctx: i64) {
    if post_create_from(ctx_permit(ctx, "title, body, author")) {
        ctx_json_created(ctx, "{\"ok\":true}")
        ret
    }
    ctx_json_errors(ctx)
}
```

`ctx_permit(ctx, fields)` extracts and whitelists the named form fields from the request. `ctx_json_errors` sends 422 with the validation error JSON automatically.

**Selective columns — `ForgeJson` builder:**

```jda
fn api_post_show(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    if post.count == 0 { ctx_not_found(ctx)  ret }
    let j = forge_json_new()
    j.field("id",    forge_result_col(post, 0, "id"))
     .field("title", forge_result_col(post, 0, "title"))
     .field_raw("published", forge_result_col(post, 0, "published"))
    ctx_json_ok(ctx, j.done())
}
```

Use `.field(key, val)` for string values (auto-escaped) and `.field_raw(key, val)` for numbers, booleans, or nested JSON.

### Handling route parameters

```jda
// app/controllers/posts_controller.jda

fn posts_show(ctx: i64) {
    let id   = ctx_param(ctx, "id")
    let post = post_find(id)
    if post.count == 0 {
        ctx_not_found(ctx)
        ret
    }
    ctx_render(ctx, view_posts_show(ctx, post))
}
```

### Security helpers

Always escape user-supplied strings before putting them in HTML or JSON:

| Function | Use |
|---|---|
| `forge_h(s)` | HTML-escape — converts `<`, `>`, `&`, `"` to entities |
| `forge_json_escape(s)` | JSON-escape — backslash-escapes special characters |
| `forge_csrf_token(ctx)` | CSRF token for the current session (put in a hidden form field) |

---

## Running tests

Forge's test runner drives requests through the real router without opening a network socket. Tests live in `test/` and are compiled into a separate binary.

### Writing a test

```jda
// test/test_posts.jda

fn test_posts_index() {
    forge_get(posts_path).ok(200).has("Blog Posts")
}

fn test_post_create_valid() {
    let body = "title=Hello+World&body=This+is+a+test+post+body&author=Alice"
    forge_post(posts_path, body).redirect()
}

fn test_post_create_missing_title() {
    forge_post(posts_path, "title=&body=Some+body+text&author=Alice").redirect()
}

fn test_post_show_not_found() {
    forge_get(post_path("99999")).ok(404)
}

fn test_post_delete() {
    forge_delete(post_path("1")).redirect()
}
```

Tests are plain functions whose names start with `test_`. The runner discovers them automatically — no registration needed. Path helpers (`posts_path`, `post_path("1")`) are defined in `config/routes.jda` and in scope for all test files.

### Running the tests

```bash
forge test
# compiles test_runner, then: FORGE_ENV=test ./test_runner
```

In test mode (`FORGE_ENV=test`):
- The app loads `.env.test`
- SMTP is disabled
- `forge_get/post/put/delete` send requests through the router in-process
- Responses are captured in memory — no sockets, no ports

### Test assertions

Assertions chain off the response via UFCS:

| Method | What it asserts |
|---|---|
| `.ok(code)` | Status matches `code` exactly |
| `.redirect()` | Any 3xx status |
| `.has(s)` | Body contains substring `s` |
| `.not_has(s)` | Body does not contain substring `s` |

All assertion methods return the response so you can chain multiple checks:

```jda
forge_get(posts_path).ok(200).has("Blog Posts").not_has("error")
```

When you need to inspect the response directly:

```jda
let res    = forge_get(posts_path)
let body   = res.body    // []i8
let status = res.status  // i32
```

### Setting up .env.test

Create `.env.test` with a separate test database so tests run against a clean, disposable database:

```bash
FORGE_ENV=test
DATABASE_URL=postgres://postgres:postgres@localhost:5432/myapp_test
APP_SECRET=test-secret-not-used-in-production
```

Create the test database once:

```bash
createdb myapp_test
```

Forge runs migrations at startup, so the schema is always up to date.

---

## Environment-specific behaviour

`FORGE_ENV` controls which `.env.*` file is loaded and how the app behaves:

```bash
forge server -e development    # loads .env.development, debug logging
forge server -e production    # loads .env.production, info logging
forge test   # loads .env.test, SMTP disabled
```

`.env` file summary:

| File | Committed? | Purpose |
|---|---|---|
| `.env` | Yes | Shared defaults (e.g. `FORGE_ENV=development`, `APP_PORT=8080`) |
| `.env.example` | Yes | Template — documents what variables are required |
| `.env.development` | No | Local dev secrets — `DATABASE_URL`, `APP_SECRET` |
| `.env.staging` | No | Staging server values |
| `.env.production` | No | Production secrets |
| `.env.test` | Yes (no secrets) | Test database URL and dummy secrets |

Never commit `.env.development`, `.env.staging`, or `.env.production`. They are gitignored by default.

---

## Next steps

Once your project is running and you have a feel for the request cycle, these guides cover the areas you will hit next:

- **[blog-example.md](blog-example.md)** — A complete multi-resource application (posts + comments, sessions, flash messages, CSRF, soft delete, migrations). The best reference for how the layers fit together at real scale.

- **[libraries.md](libraries.md)** — Adding third-party libraries via `Forgefile`, pinning versions, writing and publishing your own libraries, and using local libraries during development.

- **[overriding.md](overriding.md)** — Four patterns for customizing library behavior: wrapper functions, patch files, middleware replacement, and model callback injection. Covers when each approach is appropriate and how to keep patches maintainable.

### Common next tasks

**Add a second resource** — run `forge generate scaffold Comment post_id:integer body:text author:string`. The scaffold appends `resources "comments"` to `config/routes.jda` automatically.

**Add a library** — edit `Forgefile` to add a `lib` line, run `forge install`, and the Makefile picks it up automatically.

**Deploy** — run `forge build -e production`, copy the `app` binary and `db/migrate/` to the server, set environment variables, and run `./app`. The binary has no runtime dependencies.

**Override a library function** — create a `patches/` directory, write your replacement function, and add `$(wildcard patches/*.jda)` to `SRC` in the Makefile. See [overriding.md](overriding.md) for the full procedure.
