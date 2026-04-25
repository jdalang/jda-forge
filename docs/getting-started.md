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

Jda compiles one source file. Forge works around this by having your Makefile concatenate all your `.jda` files into `_build/app.jda` before invoking the compiler. The file order is deliberate: `config.jda` goes first (it defines constants and `load_env`), then models, then views, then routes, and finally `main.jda`. Libraries arrive via `--include` flags, which are processed before your app source.

The upshot: **every function in your project is global**. There are no modules, no namespacing, no import statements. By convention, name your functions with a prefix that reflects where they live — `post_create`, `tmpl_layout`, `handle_posts_index`.

### UFCS — Uniform Function Call Syntax

Jda supports method-style chaining on any value. `post_q().where_eq("published", "true").order_desc("created_at").exec()` is valid even though `post_q()` returns a plain `&ForgeQuery` pointer and there are no classes. Each call in the chain is just a function that takes its left-hand side as the first argument. You can chain off anything — it is syntax sugar, not object orientation.

### No GC — explicit allocation, no hidden cost

Jda has no garbage collector. Memory is allocated with `alloc_pages(n)`, which gives you `n * 4096` bytes of heap. Forge manages per-request arenas for you (the context allocator), so inside a handler you rarely call `alloc_pages` directly for small things. For building larger buffers — an HTML response assembled from many parts, for example — you allocate explicitly:

```jda
let buf: &i8 = alloc_pages(8)   // 32 KiB
let pos = 0i64
// ... write into buf[pos], increment pos ...
ctx_html(ctx, 200, buf[0..pos])
```

The benefit is predictable latency: no pauses, no stop-the-world events, no surprises under load.

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

**entr** (optional) — used by `make watch` for live reload. Install with your system package manager (`brew install entr`, `apt install entr`, etc.).

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
  config.jda            # load_env() and app_config()
  main.jda              # middleware registration, routes, server start
  .env                  # FORGE_ENV=development (shared defaults, commit it)
  .env.example          # template for per-environment secrets
  .gitignore
  models/               # query functions, validations, callbacks
  views/                # HTML helpers, layout, partials
  routes/               # HTTP handlers
  test/                 # request-level tests
  db/
    migrations/         # numbered .sql files
  libs/                 # installed libraries (gitignored except forge.jda)
```

### File-by-file

**`Forgefile`** declares dependencies, similar to a Gemfile or package.json:

```
forge "github.com/jdalang/jda-forge" version "3.0.0"
```

Additional libraries are added with `lib` lines. See [libraries.md](libraries.md) for the full format.

**`Forgefile.lock`** records the exact git SHA for every dependency after `forge install` resolves them. Commit this file. It ensures every developer and every CI run installs identical code.

**`Makefile`** handles three operations: `make` (or `make build`) compiles the app, `make run` compiles and starts it, `make test` compiles and runs the test suite. It uses GNU Make's `wildcard` to pick up new `.jda` files automatically — you do not need to edit it when you add a model or a route file.

**`config.jda`** defines two functions that `main.jda` calls first:
- `load_env()` — reads `.env` then the environment-specific file (`.env.development`, `.env.production`, etc.) based on `$FORGE_ENV`.
- `app_config()` — reads environment variables into a `ForgeConfig` struct and sets the log level.

**`main.jda`** is the entry point. It calls `load_env`, creates the app, registers middleware, registers routes, runs migrations, and starts listening.

**`.env`** holds defaults that are safe to commit — typically just `FORGE_ENV=development` and `APP_PORT=8080`. Per-environment files (`.env.development`, `.env.production`) hold secrets and are gitignored.

---

## Project structure

Here is where each kind of code lives and why.

| Directory / file | What goes here |
|---|---|
| `config.jda` | `load_env()`, `app_config()`, app-wide constants |
| `models/` | One file per resource — query functions, validations, create/update/delete |
| `views/` | `tmpl_layout()`, `tmpl_flash()`, per-resource row/card helpers |
| `routes/` | One file per resource — handler functions, one `register_*_routes()` per file |
| `test/` | One file per resource — `forge_test_get/post/delete`, `forge_assert_*` |
| `db/migrations/` | Numbered SQL files: `001_create_posts.sql`, `002_create_comments.sql`, … |
| `libs/` | Installed libraries (managed by `forge install`, mostly gitignored) |
| `patches/` | Optional — overrides for library functions (see [overriding.md](overriding.md)) |
| `main.jda` | Wires everything together — always the last file compiled |

**Naming convention:** functions are prefixed by their layer and resource. A model function is `post_create`, a route handler is `handle_posts_create`, a view helper is `tmpl_post_row`. This keeps everything findable without modules.

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
make run
```

The Makefile:
1. Concatenates all source files into `_build/app.jda`
2. Compiles with `jda build --include libs/forge.jda _build/app.jda -o app`
3. Runs `./app`

Forge runs migrations automatically on startup (`forge_migration_run("db/migrations")`), so your tables are created on first launch.

Visit `http://localhost:8080` in a browser. You should get a 404 — that is correct; no routes are registered yet.

### 4. Live reload (optional)

```bash
make watch
```

This uses `entr` to recompile and restart the server whenever any source file changes.

---

## The build pipeline

Understanding the build pipeline prevents a whole class of confusing compiler errors.

### Why concatenation?

Jda compiles a single file. To support a multi-file project, the Makefile concatenates everything into one file before the compiler sees it. This is explicit and transparent — you can inspect `_build/app.jda` at any time to see exactly what the compiler received.

### The Makefile in full

```makefile
APP  = myapp
OUT  = _build/$(APP).jda

CONFIG  = config.jda
MODELS  = $(wildcard models/*.jda)
VIEWS   = $(wildcard views/*.jda)
ROUTES  = $(wildcard routes/*.jda)
PATCHES = $(wildcard patches/*.jda)
MAIN    = main.jda

SRC = $(CONFIG) $(MODELS) $(VIEWS) $(ROUTES) $(PATCHES) $(MAIN)

TEST_SRC = $(CONFIG) $(MODELS) $(VIEWS) $(ROUTES) $(wildcard test/*.jda)
TEST_OUT = _build/test.jda

all: build

$(OUT): $(SRC)
	@mkdir -p _build
	@cat $(SRC) > $(OUT)

build: $(OUT)
	jda build --include libs/forge.jda $(OUT) -o $(APP)

run: build
	./$(APP)

test: $(TEST_OUT)
	jda build --include libs/forge.jda $(TEST_OUT) -o test_runner
	FORGE_ENV=test ./test_runner

$(TEST_OUT): $(TEST_SRC)
	@mkdir -p _build
	@cat $(TEST_SRC) > $(TEST_OUT)

clean:
	rm -rf _build $(APP) test_runner
```

### Order rules

The order of `$(SRC)` is not arbitrary:

| Position | File(s) | Why |
|---|---|---|
| First | `config.jda` | Defines `load_env`, `app_config`, and constants everything else uses |
| Second | `models/*.jda` | Defines types and query functions that views and routes call |
| Third | `views/*.jda` | Defines template helpers that routes call |
| Fourth | `routes/*.jda` | Defines handlers and `register_*_routes` functions |
| Fifth | `patches/*.jda` | Overrides library functions — must come after everything else except main |
| Last | `main.jda` | References `register_*_routes` and all middleware — must see all of the above |

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
db/migrations/001_create_posts.sql   # CREATE TABLE posts (...)
models/post.jda                      # post_find, post_all, post_create, post_update,
                                     # post_delete, post_validate
routes/posts.jda                     # 7 handlers + register_post_routes()
test/test_posts.jda                  # request tests for each handler
```

### Wire it up in main.jda

Open `main.jda` and add `register_post_routes(app)` after the middleware block:

```jda
fn main() {
    load_env()
    let cfg = app_config()
    let app = app_new_config(cfg)

    app_use(app, fn_addr(forge_logger))
    app_use(app, fn_addr(forge_request_id))
    app_use(app, fn_addr(forge_secure_headers))
    app_use(app, fn_addr(forge_session_start))
    app_use(app, fn_addr(forge_csrf))

    register_post_routes(app)    // ← add this

    forge_migration_run("db/migrations")
    app_listen(app, 8080)
}
```

Run `make run`. The full CRUD interface for posts is now live:

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

```jda
// models/post.jda

fn post_q() -> &ForgeQuery { ret forge_q("posts") }

fn post_all() -> &ForgeResult {
    ret forge_q("posts").order_desc("created_at").exec()
}

fn post_find(id: []i8) -> &ForgeResult {
    ret forge_q("posts").where_eq("id", id).exec()
}

fn post_validate(title: []i8, body: []i8, author: []i8) -> &ForgeErrors {
    let e = forge_errors_new()
    forge_validate_presence(e, "title",  title)
    forge_validate_length  (e, "title",  title, 2, 255)
    forge_validate_presence(e, "body",   body)
    forge_validate_presence(e, "author", author)
    ret e
}

fn post_create(title: []i8, body: []i8, author: []i8) -> bool {
    ret forge_insert("posts",
        "title",  title,
        "body",   body,
        "author", author)
}

fn post_update(id: []i8, title: []i8, body: []i8) -> bool {
    ret forge_update("posts", id, "title", title, "body", body)
}

fn post_delete(id: []i8) -> bool {
    ret forge_soft_delete("posts", id)
}
```

`forge_q("posts")` automatically excludes soft-deleted rows (`deleted_at IS NOT NULL`). You can chain any query method off `post_q()`:

```jda
let res = post_q()
    .where_ilike("title", "%jda%")
    .order_desc("created_at")
    .page(2, 20)
    .exec()
```

---

## Writing a handler manually

Sometimes you want a route that does not fit the CRUD scaffold — an API endpoint, a search page, a webhook receiver. Here is how to build one from scratch.

### Step 1 — create the route file

```jda
// routes/hello.jda

fn handle_hello(ctx: i64) {
    let name = ctx_query(ctx, "name")
    if name.len == 0 { name = "World" }
    ctx_html(ctx, 200, "<h1>Hello, " + forge_h(name) + "</h1>")
}

fn register_hello_routes(app: i64) {
    app_get(app, "/hello", fn_addr(handle_hello))
}
```

### Step 2 — register it in main.jda

```jda
register_hello_routes(app)
```

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
| `ctx_json(ctx, status, body)` | JSON response (`Content-Type: application/json`) |
| `ctx_text(ctx, status, body)` | Plain text response |
| `ctx_redirect(ctx, path)` | 302 redirect |
| `ctx_not_found(ctx)` | 404 response |
| `ctx_too_many_requests(ctx)` | 429 response |
| `ctx_set_header(ctx, name, val)` | Set a response header before sending |

### A JSON API endpoint

```jda
// routes/api.jda

fn handle_api_posts(ctx: i64) {
    let posts = post_all()
    let buf: &i8 = alloc_pages(4)
    let pos = 0i64

    let open = "["
    loop i in 0..open.len { buf[pos] = open[i]  pos = pos + 1 }

    loop r in 0..posts.count {
        if r > 0 {
            buf[pos] = ','
            pos = pos + 1
        }
        let id     = forge_result_col(posts, r, "id")
        let title  = forge_result_col(posts, r, "title")
        let author = forge_result_col(posts, r, "author")
        let entry = "{\"id\":" + id + ",\"title\":\"" + forge_json_escape(title)
                  + "\",\"author\":\"" + forge_json_escape(author) + "\"}"
        loop i in 0..entry.len { buf[pos] = entry[i]  pos = pos + 1}
    }

    let close = "]"
    loop i in 0..close.len { buf[pos] = close[i]  pos = pos + 1 }

    ctx_json(ctx, 200, buf[0..pos])
}

fn register_api_routes(app: i64) {
    app_get(app, "/api/posts", fn_addr(handle_api_posts))
}
```

### Handling route parameters

```jda
fn handle_posts_show(ctx: i64) {
    let id   = ctx_param(ctx, "id")
    let post = post_find(id)
    if post.count == 0 {
        ctx_not_found(ctx)
        ret
    }
    let title = forge_result_col(post, 0, "title")
    let body  = forge_result_col(post, 0, "body")
    // ... build and send response
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
    let res = forge_test_get("/posts")
    forge_assert_status  (res, 200)
    forge_assert_body_has(res, "Blog Posts")
}

fn test_post_create_valid() {
    let body = "title=Hello+World&body=This+is+a+test+post+body&author=Alice"
    let res  = forge_test_post("/posts", body)
    forge_assert_redirect(res)
}

fn test_post_create_missing_title() {
    let body = "title=&body=Some+body+text&author=Alice"
    let res  = forge_test_post("/posts", body)
    forge_assert_redirect(res)   // redirects back to form with flash error
}

fn test_post_show_not_found() {
    let res = forge_test_get("/posts/99999")
    forge_assert_status(res, 404)
}

fn main() {
    forge_dotenv_load(".env.test")
    forge_test_init()

    forge_test("GET /posts",               fn_addr(test_posts_index))
    forge_test("POST /posts valid",        fn_addr(test_post_create_valid))
    forge_test("POST /posts missing title",fn_addr(test_post_create_missing_title))
    forge_test("GET /posts/99999",         fn_addr(test_post_show_not_found))

    forge_test_run()
}
```

### Running the tests

```bash
make test
# compiles test_runner, then: FORGE_ENV=test ./test_runner
```

In test mode (`FORGE_ENV=test`):
- The app loads `.env.test`
- SMTP is disabled
- `forge_test_get/post/delete` send requests through the router in-process
- Responses are captured in memory — no sockets, no ports

### Test assertions

| Assertion | Checks |
|---|---|
| `forge_assert_status(res, 200)` | Response has the given HTTP status code |
| `forge_assert_redirect(res)` | Response is a 3xx redirect |
| `forge_assert_body_has(res, "text")` | Response body contains the substring |
| `forge_assert_body_eq(res, "text")` | Response body exactly equals the string |
| `forge_assert_header(res, "name", "val")` | Response has a header with the given value |

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
FORGE_ENV=development make run    # loads .env.development, debug logging
FORGE_ENV=production  make run    # loads .env.production, info logging
FORGE_ENV=test        make test   # loads .env.test, SMTP disabled
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

**Add a second resource** — run `forge generate scaffold Comment post_id:integer body:text author:string`, add the migration FK, and call `register_comment_routes(app)` in `main.jda`.

**Add a library** — edit `Forgefile` to add a `lib` line, run `forge install`, and the Makefile picks it up automatically.

**Deploy** — compile with `FORGE_ENV=production make build`, copy the `app` binary and the `db/migrations/` directory to the server, set environment variables, and run `./app`. The binary has no runtime dependencies.

**Override a library function** — create a `patches/` directory, write your replacement function, and add `$(wildcard patches/*.jda)` to `SRC` in the Makefile. See [overriding.md](overriding.md) for the full procedure.
