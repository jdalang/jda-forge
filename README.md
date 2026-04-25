# JDA Forge

A full-stack web framework for the [Jda language](https://github.com/jdalang/jda). Routing, ORM, migrations, controllers, views, testing, background jobs, mailer, WebSocket, SSE, caching, file uploads, i18n, and more — in a single `--include` file.

---

## Installation

### One-line install (latest)

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh
```

### Install a specific version

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh -s -- --version v3.0.0
```

This clones Forge to `~/.jda/forge/`, checks out the requested tag, links the `forge` CLI to `~/.jda/bin/`, and patches your shell rc.

### Manual install

```bash
git clone https://github.com/jdalang/jda-forge.git ~/.jda/forge
echo 'export PATH="$HOME/.jda/bin:$PATH"'            >> ~/.zshrc
echo 'export JDA_FORGE="$HOME/.jda/forge/forge.jda"' >> ~/.zshrc
ln -sf ~/.jda/forge/bin/forge ~/.jda/bin/forge
source ~/.zshrc
```

### Verify

```bash
forge version        # JDA Forge CLI v3.0.0
```

### Upgrade the CLI

```bash
forge self-update                      # update to latest
forge self-update --version v3.1.0    # update to specific version
```

---

## Quick Start

```jda
fn handle_root(ctx: i64) {
    ctx_html(ctx, 200, "<h1>Hello from Forge</h1>")
}

fn main() {
    let app = app_new()
    app_use(app, fn_addr(forge_logger))
    app_get(app, "/", fn_addr(handle_root))
    app_listen(app, 8080)
}
```

Build and run:

```bash
jda build --include forge.jda app.jda -o app
./app
```

---

## Examples

| Example | What it shows |
|---|---|
| [`examples/hello.jda`](examples/hello.jda) | Route groups, middleware, request-id |
| [`examples/crud.jda`](examples/crud.jda) | JWT-protected API, login, /me endpoint |
| [`examples/websocket.jda`](examples/websocket.jda) | WebSocket echo chat server |
| [`examples/static_files.jda`](examples/static_files.jda) | SPA shell + static file serving |
| [`examples/blog/`](examples/blog/) | Full multi-file app — posts + comments CRUD, sessions, CSRF, flash, migrations, tests, multi-environment config |

The blog example is the best starting point for a real application.

---

## Project Layout (multi-file apps)

Use the scaffold template. The Makefile concatenates all source files before compilation:

```
scaffold/
  Makefile
  config.jda            # ForgeConfig, constants, secrets
  .env.example          # DATABASE_URL, SMTP_HOST, FORGE_ENV, APP_SECRET
  middleware/           # app-specific middleware
  models/               # model definitions, validations, associations
  controllers/          # before/after action filters
  views/                # templates and partials
  routes/               # route handlers and registration
  concerns/             # shared behavior (timestamps, tags, audit)
  db/migrations/        # SQL migration files
  test/                 # test files
  main.jda              # app wiring
```

```bash
cd scaffold
make        # build
make run    # build + run
make test   # run test suite
make watch  # rebuild on file change (requires entr)
```

---

## CLI

### New project

```bash
forge new myblog
cd myblog
forge install                    # install forge.jda into libs/
cp .env.example .env.development # fill in DATABASE_URL, APP_SECRET
make run
```

### Generators

```bash
# scaffold: model + controller + migration in one shot
forge generate scaffold Post title:string body:text user:references

# individual generators
forge generate model    Comment body:text post:references author:string
forge generate controller Posts
forge generate migration AddPublishedToPosts published:boolean
```

### Library management

```bash
forge add forge-markdown          # add from github.com/jdalang/forge-markdown
forge add mylib https://github.com/org/jda-mylib   # custom URL
forge install                     # install all from Forgefile
forge update                      # update all libs
forge list                        # show installed libs
```

---

## Routing

```jda
app_get   (app, "/users",     fn_addr(list_users))
app_post  (app, "/users",     fn_addr(create_user))
app_get   (app, "/users/:id", fn_addr(show_user))
app_put   (app, "/users/:id", fn_addr(update_user))
app_delete(app, "/users/:id", fn_addr(delete_user))
app_patch (app, "/users/:id", fn_addr(patch_user))
```

### Route Groups

```jda
let api = app_group(app, "/api/v1")
group_use(&api, fn_addr(forge_jwt_auth))      // scoped middleware
group_get (&api, "/users",     fn_addr(list_users))
group_post(&api, "/users",     fn_addr(create_user))
group_get (&api, "/users/:id", fn_addr(show_user))
```

### Custom 404 / 500

```jda
app_not_found(app, fn_addr(my_404))
app_on_error (app, fn_addr(my_500))
```

---

## Context API

Every handler and middleware receives `ctx: i64`.

### Request

```jda
ctx_param (ctx, "id")                  // :id from path
ctx_query (ctx, "page")                // ?page=2
ctx_query_default(ctx, "page", "1")    // with fallback
ctx_form  (ctx, "email")               // POST body field
ctx_form_default(ctx, "role", "user")  // with fallback
ctx_header(ctx, "Accept")
ctx_method(ctx)                        // "GET", "POST", …
ctx_path  (ctx)                        // "/users/42"
ctx_ip    (ctx)                        // client IP, proxy-aware
ctx_body  (ctx)                        // raw body []i8
ctx_body_json(ctx)                     // parsed JSON
ctx_cookie(ctx, "session")
ctx_format(ctx)                        // "json" / "html" / "xml"
```

### Response

```jda
ctx_text(ctx, 200, "hello")
ctx_json(ctx, 200, "{\"ok\":true}")
ctx_html(ctx, 200, "<h1>Hi</h1>")
ctx_redirect(ctx, "/login")            // 302
ctx_redirect_perm(ctx, "/new")         // 301
ctx_download(ctx, body, "report.csv")  // attachment
ctx_set_header(ctx, "X-Foo", "bar")
ctx_set_cookie(ctx, "tok", val, 3600)
ctx_del_cookie(ctx, "tok")
```

Status helpers:

```jda
ctx_ok(ctx, body)          // 200
ctx_created(ctx, body)     // 201
ctx_accepted(ctx, body)    // 202
ctx_no_content(ctx)        // 204
ctx_not_modified(ctx)      // 304
ctx_bad_request(ctx, msg)  // 400
ctx_unauthorized(ctx)      // 401
ctx_forbidden(ctx)         // 403
ctx_not_found(ctx)         // 404
ctx_conflict(ctx, msg)     // 409
ctx_unprocessable(ctx, msg)// 422
ctx_too_many_requests(ctx) // 429
ctx_internal_error(ctx, m) // 500
```

### Per-request Store

```jda
ctx_set(ctx, "user_id", ptr_as_i64)
let uid: i64 = ctx_get(ctx, "user_id")
```

---

## Middleware

### Built-in

```jda
app_use(app, fn_addr(forge_logger))          // request log
app_use(app, fn_addr(forge_request_id))      // X-Request-Id header
app_use(app, fn_addr(forge_secure_headers))  // HSTS, X-Frame, CSP
app_use(app, fn_addr(forge_cors))            // CORS headers
app_use(app, fn_addr(forge_rate_limit))      // 100 req/min per IP
app_use(app, fn_addr(forge_no_cache))        // no-store headers
app_use(app, fn_addr(forge_recover))         // panic → 500
app_use(app, fn_addr(forge_session_start))   // cookie sessions
app_use(app, fn_addr(forge_csrf))            // CSRF token check
app_use(app, fn_addr(forge_jwt_auth))        // Bearer JWT auth
app_use(app, fn_addr(forge_basic_auth))      // HTTP Basic auth
app_use(app, fn_addr(forge_proxy_headers))   // X-Forwarded-For
app_use(app, fn_addr(forge_cache_middleware))// ETag + 304
app_use(app, fn_addr(forge_etag_middleware)) // auto ETag
```

After-middleware (runs after handler):

```jda
app_after(app, fn_addr(my_after_fn))
```

### Custom Middleware

```jda
fn require_login(ctx: i64) {
    let uid = ctx_session_get(ctx, "user_id")
    if uid.len == 0 {
        ctx_redirect(ctx, "/login")
    }
}
```

---

## Sessions & Flash

Requires `forge_session_start` middleware.

```jda
ctx_session_get  (ctx, "user_id")
ctx_session_set  (ctx, "user_id", "42")
ctx_session_del  (ctx, "user_id")
ctx_session_clear(ctx)

ctx_flash_set(ctx, "notice", "Saved!")
ctx_flash_get(ctx, "notice")   // consumed on first read
```

---

## CSRF Protection

Requires `forge_session_start` + `forge_csrf` middleware.

```jda
// Embed in HTML forms
let tok = forge_csrf_token(ctx)
// <input type=hidden name=_csrf value="<tok>">
```

---

## Auth

### JWT

```jda
forge_set_jwt_secret("your-secret")
app_use(app, fn_addr(forge_jwt_auth))
// Authorization: Bearer <token>
// ctx_get(ctx, "jwt_sub") -> user id
```

### Basic Auth

```jda
forge_set_basic_auth("admin", "pass")
app_use(app, fn_addr(forge_basic_auth))
```

---

## Database (PostgreSQL)

### Configuration

```jda
let cfg = forge_default_config()
cfg.db_url = "postgres://user:pass@localhost/mydb"
let app = app_new_config(cfg)
```

Or via environment:

```
DATABASE_URL=postgres://user:pass@localhost/mydb
```

### Raw Queries

```jda
forge_db_exec ("INSERT INTO users (email) VALUES ($1)", email)
forge_db_query("SELECT id, email FROM users WHERE id = $1", id)
```

### Query Builder

```jda
let res = forge_q("users")
    .where("active", "=", "true")
    .where("role",   "=", "admin")
    .order("created_at", "DESC")
    .limit(20)
    .exec()

// Helpers
forge_find   ("users", id)                // SELECT * WHERE id = ?
forge_find_by("users", "email", email)    // SELECT * WHERE col = ?
forge_all    ("users")                    // SELECT *
forge_q_count(q)                          // SELECT COUNT(*)
forge_q_first(q)                          // LIMIT 1
```

### Associations

```jda
let user  = forge_belongs_to("users", post_user_id)  // find parent
let posts = forge_has_many("posts", "user_id", uid)   // find children
let prof  = forge_has_one ("profiles", "user_id", uid)
```

### Transactions

```jda
let fd = forge_tx_begin()
if fd < 0 { /* handle error */ ret }
let ok = forge_tx_exec(fd, "UPDATE accounts SET balance = balance - 100 WHERE id = $1", from_id)
if !ok { forge_tx_rollback(fd)  ret }
forge_tx_commit(fd)
```

### Serialization

```jda
let res  = forge_all("users")
let json = forge_result_to_json(res)         // JSON array
let obj  = forge_row_to_json(res, 0)         // single row
```

### Soft Delete

```jda
forge_soft_delete("users", id)   // sets deleted_at
forge_restore    ("users", id)   // clears deleted_at
forge_purge      ("users", id)   // hard delete
// forge_q("users") automatically excludes deleted rows
```

### Migrations

```jda
forge_migration_run("db/migrations")   // runs pending .sql files
```

---

## Validations

```jda
let errs = forge_errors_new()
forge_validate_presence      (errs, "email",    email)
forge_validate_format_email  (errs, "email",    email)
forge_validate_length        (errs, "password", password, 8, 128)
forge_validate_min_length    (errs, "name",     name, 2)
forge_validate_numericality  (errs, "age",      age)
forge_validate_confirmation  (errs, "password", password, confirm)
forge_validate_inclusion     (errs, "role",     role, "admin,user,guest")

if forge_errors_any(errs) {
    ctx_unprocessable(ctx, forge_errors_json(errs))
    ret
}
```

---

## Callbacks

```jda
// CB_BEFORE_CREATE  CB_BEFORE_UPDATE  CB_BEFORE_SAVE  CB_BEFORE_DELETE
// CB_AFTER_CREATE   CB_AFTER_UPDATE   CB_AFTER_SAVE

forge_callback_add("users", CB_BEFORE_SAVE,   fn_addr(hash_password))
forge_callback_add("users", CB_AFTER_CREATE,  fn_addr(send_welcome_email))

fn hash_password(row_ptr: i64) -> bool {
    // modify row, return false to abort
    ret true
}
```

---

## Controllers

```jda
let ctrl = forge_ctrl_new()
forge_ctrl_before(ctrl, fn_addr(require_login), "")         // all actions
forge_ctrl_before(ctrl, fn_addr(require_admin), "destroy")  // only destroy

fn index(ctx: i64) {
    forge_ctrl_dispatch(ctrl, ctx, fn_addr(do_index), "index")
}
fn do_index(ctx: i64) {
    ctx_json(ctx, 200, forge_result_to_json(forge_all("users")))
}
```

### Strong Params

```jda
let email = forge_permit_json(ctx, "email,name,role")
let name  = forge_permit_form(ctx, "email,name", "name")
```

### Pagination

```jda
let page = ctx_query_default(ctx, "page", "1")
let res  = forge_paginate_query(forge_q("posts").order("id", "DESC"), str_to_i64(page), 20)
let meta = forge_page_meta_json(total, str_to_i64(page), 20)
```

### Content Negotiation

```jda
let fmt = ctx_format(ctx)   // "json" / "html" / "xml"
if str_eq(fmt, "json") {
    ctx_json(ctx, 200, forge_result_to_json(res))
} else {
    ctx_html(ctx, 200, render_users(res))
}
```

---

## Views & Templates

### ERB Rendering

```jda
let vars = erb_vars_new()
erb_vars_set(vars, "name", 4, "Alice", 5)
ctx_render(ctx, 200, "Hello, <%= name %>!", vars)
```

### Partials

```jda
forge_template_register("user_card", "<div><%= name %></div>")
let html = forge_partial("user_card", vars)
```

### View Helpers

```jda
forge_link_to       ("Edit", "/users/1/edit")
forge_link_to_delete("Delete", "/users/1", csrf_token)
forge_button_to     ("Submit", "/posts", "POST")
forge_form_tag_open ("/users", "POST", csrf_token)
forge_input_tag     ("text", "email", "")
forge_label_tag     ("email", "Email address")
forge_textarea_tag  ("body", "", 6, 60)
forge_select_tag    ("role", "admin,user,guest", "user")
forge_submit_tag    ("Save")
forge_form_tag_close()

forge_path    ("users")           // "/users"
forge_path_id ("users", "42")    // "/users/42"
forge_path_new("users")          // "/users/new"
forge_path_edit("users", "42")   // "/users/42/edit"
```

### content_for / yield

```jda
forge_content_for  (ctx, "title", "My Page")
forge_yield_content(ctx, "title")
```

### Utility Helpers

```jda
forge_html_escape(src, dst_buf)
forge_truncate   (s, 100)
forge_pluralize  (count, "post", "posts")
```

---

## Background Jobs

```jda
forge_jobs_start(8)   // start 8 worker goroutines

fn send_email_job(arg: i64) {
    // arg is a pointer cast to i64
}

forge_job_enqueue(fn_addr(send_email_job), user_ptr as i64)
```

---

## Mailer

```jda
let cfg = forge_default_config()
cfg.smtp_host = "smtp.example.com"
cfg.smtp_port = 587
cfg.smtp_user = "user@example.com"
cfg.smtp_pass = "secret"

forge_mail_send("to@example.com", "Welcome!", "<h1>Hello</h1>")
forge_mail_send_async("to@example.com", "Welcome!", body)  // non-blocking
```

---

## WebSocket

```jda
app_ws(app, "/ws/chat", fn_addr(ws_handler))

fn ws_handler(ctx: i64) {
    if ctx_upgrade_ws(ctx) {
        let fd = ctx_fd(ctx)
        let buf = [4096]i8
        loop {
            let n = forge_ws_recv(fd, buf, 4096)
            if n <= 0 { break }
            forge_ws_send_text(fd, buf[0..n])
        }
        forge_ws_close(fd)
    }
}
```

---

## Server-Sent Events

```jda
app_get(app, "/events", fn_addr(sse_handler))

fn sse_handler(ctx: i64) {
    let fd = ctx_sse_start(ctx)
    if fd < 0 { ret }
    loop {
        forge_sse_send(fd, "update", "{\"count\":1}")
        // sleep or block on channel
    }
    forge_sse_close(fd)
}
```

---

## Static Files

```jda
app_static(app, "/static", "./public")
// GET /static/app.js  →  ./public/app.js
```

---

## Caching

```jda
// Fragment cache
forge_cache_set("users:list", json_body, 300)
let cached = forge_cache_get("users:list")
forge_cache_has("users:list")
forge_cache_del("users:list")
forge_cache_clear()

// ETag / 304 middleware
app_use(app, fn_addr(forge_etag_middleware))
app_use(app, fn_addr(forge_cache_middleware))
```

---

## File Uploads

```jda
// multipart/form-data
let upload = ctx_multipart_file(ctx, "avatar")
if upload.size == 0 { ctx_bad_request(ctx, "no file")  ret }

forge_validate_upload_type(upload, "image/jpeg,image/png")
forge_validate_upload_size(upload, 5 * 1024 * 1024)   // 5 MB

let path = forge_upload_save(upload, "./uploads")
// serve via app_static(app, "/uploads", "./uploads")
```

---

## I18n

```jda
forge_i18n_load("en", "locales/en.txt")
forge_i18n_load("es", "locales/es.txt")

// locales/en.txt
// welcome = Welcome, %s!
// errors.required = is required

let msg = forge_t(ctx, "welcome")
```

---

## Concerns

### Timestamps

```jda
// On insert
forge_timestamps_create("posts", id)   // sets created_at, updated_at

// On update
forge_timestamps_update("posts", id)   // sets updated_at
```

### Tags

```jda
forge_tags_add   ("posts", post_id, "ruby")
forge_tags_remove("posts", post_id, "ruby")
forge_tags_for   ("posts", post_id)           // returns ForgeResult
forge_tags_find  ("posts", "ruby")            // all records with tag
```

### Audit Log

```jda
forge_audit_log(ctx, "users", "update", user_id)
// writes to forge_audit_log table
```

---

## Environment & Config

```jda
forge_dotenv_load(".env")        // load .env file

forge_env()                      // "development" / "test" / "production"
forge_env_is("production")       // bool
forge_env_get("DATABASE_URL")    // read any env var

forge_log_level_set(FORGE_LOG_INFO)
forge_log_debug("msg")
forge_log_info ("msg")
forge_log_warn ("msg")
forge_log_error("msg")
```

### Config Struct

```jda
let cfg        = forge_default_config()
cfg.db_url     = forge_env_get("DATABASE_URL")
cfg.smtp_host  = forge_env_get("SMTP_HOST")
cfg.smtp_port  = 587
cfg.smtp_user  = forge_env_get("SMTP_USER")
cfg.smtp_pass  = forge_env_get("SMTP_PASS")
cfg.secret_key = forge_env_get("APP_SECRET")
let app        = app_new_config(cfg)
```

---

## Testing

```jda
fn test_create_user() {
    let res = forge_test_post("/users", "email=alice@example.com")
    forge_assert_status(res, 302)

    let show = forge_test_get("/users/1")
    forge_assert_status  (show, 200)
    forge_assert_body_has(show, "alice@example.com")
}

fn test_validation() {
    let res = forge_test_post("/users", "email=")
    forge_assert_status  (res, 422)
    forge_assert_body_has(res, "required")
}

fn main() {
    forge_test_init()
    forge_test("create user", fn_addr(test_create_user))
    forge_test("validation",  fn_addr(test_validation))
    forge_test_run()
}
```

### Assertions

```jda
forge_assert         (cond, "message")
forge_assert_eq      (a, b, "message")
forge_assert_status  (res, 200)
forge_assert_body_has(res, "substring")
forge_assert_body_eq (res, "exact body")
forge_assert_redirect(res)
```

### DB Helpers

```jda
forge_test_db_truncate("users")
forge_test_db_count   ("users")   // returns i64
```

---

## Middleware Stack (recommended order)

```jda
app_use(app, fn_addr(forge_logger))
app_use(app, fn_addr(forge_request_id))
app_use(app, fn_addr(forge_secure_headers))
app_use(app, fn_addr(forge_cors))
app_use(app, fn_addr(forge_rate_limit))
app_use(app, fn_addr(forge_session_start))
app_use(app, fn_addr(forge_csrf))
app_use(app, fn_addr(forge_etag_middleware))
```

---

## Third-Party Libraries (Forgefile)

Libraries are plain `.jda` files declared in a `Forgefile` and installed into `libs/` — the same idea as Gemfile / package.json. The Makefile auto-discovers everything in `libs/*.jda`.

### Forgefile — declare dependencies + pin versions

```
# Forgefile

forge "github.com/jdalang/jda-forge"        version "3.0.0"

lib   "github.com/jdalang/forge-markdown"   version "1.2.0"
lib   "github.com/jdalang/forge-slugify"    version "1.0.0"
lib   "github.com/myorg/jda-payments"                        # latest
```

Omitting `version` always pulls the latest default branch. Pinning a version checks out that exact git tag.

### Forgefile.lock — reproducible installs

`forge install` writes a `Forgefile.lock` recording the exact git SHA of every installed library:

```
# Forgefile.lock — commit this file
forge jda-forge   github.com/jdalang/jda-forge   v3.0.0  abc1234
lib   forge-markdown  github.com/jdalang/forge-markdown  v1.2.0  def5678
lib   forge-slugify   github.com/jdalang/forge-slugify   v1.0.0  9a8b7c6
```

Teammates run `forge install --locked` to get byte-for-byte the same versions. CI always uses `--locked`.

### Commands

```bash
forge install                                  # install from Forgefile, write lock
forge install --locked                         # install exact versions from lock (CI)
forge add forge-markdown                       # add + install from github.com/jdalang/
forge add forge-markdown --version v1.2.0     # add at a specific version
forge add mylib https://github.com/org/jda-mylib --version v2.0.0
forge update                                   # update all to latest/pinned
forge update forge-markdown                    # update one library
forge list                                     # show installed libs + lock info
```

### How it works

`forge install` clones each library into `libs/.src/<name>/`, checks out the pinned tag, copies the `.jda` file to `libs/<name>.jda`. The Makefile auto-discovers it:

```makefile
FORGE = libs/forge.jda
LIBS  = $(filter-out $(FORGE), $(wildcard libs/*.jda))
LINCS = $(addprefix --include ,$(LIBS))

build:
    jda build --include $(FORGE) $(LINCS) $(OUT) -o app
```

### Writing a library

A library is a single `.jda` file at the root of a GitHub repo. Tag releases with `git tag v1.0.0`.

```jda
// forge-slugify.jda  →  github.com/jdalang/forge-slugify

fn slugify(src: []i8, dst: &i8) -> i64 {
    let pos = 0i64
    loop i in 0..src.len {
        let c = src[i]
        if c >= 'A' && c <= 'Z' { dst[pos] = c + 32    pos = pos + 1 }
        else if c >= 'a' && c <= 'z' { dst[pos] = c     pos = pos + 1 }
        else if c >= '0' && c <= '9' { dst[pos] = c     pos = pos + 1 }
        else if pos > 0 && dst[pos-1] != '-' { dst[pos] = '-'  pos = pos + 1 }
    }
    ret pos
}
```

```jda
// in your app after: forge add forge-slugify
let buf = [256]i8
let len = slugify(title, buf)
let slug = buf[0..len]
```

### Releasing a new Forge version (maintainers)

```bash
forge release 3.1.0
# → updates version string, commits, tags v3.1.0, pushes, creates GitHub release
```

### Naming convention

Official libraries: `github.com/jdalang/forge-<name>`  
Community libraries: any git URL, pass it directly to `forge add`.

---

## Environments

Forge supports `development`, `staging`, `test`, and `production` environments via the `FORGE_ENV` environment variable and per-environment `.env` files.

### Environment files

```
.env                   # shared defaults (committed)
.env.development       # local dev overrides (gitignored)
.env.staging           # staging server values (gitignored)
.env.production        # production values (gitignored)
.env.test              # test overrides (gitignored)
```

Load the right file at startup based on `FORGE_ENV`:

```jda
fn load_env() {
    let env = forge_env_get("FORGE_ENV")
    if env.len == 0 { env = "development" }

    forge_dotenv_load(".env")

    if str_eq(env, "development") { forge_dotenv_load(".env.development") }
    else if str_eq(env, "staging")     { forge_dotenv_load(".env.staging")     }
    else if str_eq(env, "production")  { forge_dotenv_load(".env.production")  }
    else if str_eq(env, "test")        { forge_dotenv_load(".env.test")        }
}
```

### Per-environment config

```jda
fn app_config() -> ForgeConfig {
    load_env()
    let cfg = forge_default_config()
    cfg.db_url     = forge_env_get("DATABASE_URL")
    cfg.smtp_host  = forge_env_get("SMTP_HOST")
    cfg.smtp_port  = 587
    cfg.smtp_user  = forge_env_get("SMTP_USER")
    cfg.smtp_pass  = forge_env_get("SMTP_PASS")
    cfg.secret_key = forge_env_get("APP_SECRET")

    // Disable mailer in test and development
    if forge_env_is("test") || forge_env_is("development") {
        cfg.smtp_host = ""
    }

    // Verbose logging in development
    if forge_env_is("development") {
        forge_log_level_set(FORGE_LOG_DEBUG)
    } else {
        forge_log_level_set(FORGE_LOG_INFO)
    }

    ret cfg
}
```

### Example .env files

**.env** (shared baseline, commit this):
```
FORGE_ENV=development
APP_PORT=8080
```

**.env.development** (local only, gitignore):
```
DATABASE_URL=postgres://postgres:postgres@localhost/myapp_dev
SMTP_HOST=
APP_SECRET=dev-secret-not-for-production
```

**.env.staging** (staging server, gitignore):
```
DATABASE_URL=postgres://user:pass@staging-db.internal/myapp_staging
SMTP_HOST=smtp.sendgrid.net
SMTP_USER=apikey
SMTP_PASS=SG.xxxx
APP_SECRET=staging-secret-64chars
```

**.env.production** (production server, gitignore):
```
DATABASE_URL=postgres://user:pass@prod-db.internal/myapp_prod
SMTP_HOST=smtp.sendgrid.net
SMTP_USER=apikey
SMTP_PASS=SG.xxxx
APP_SECRET=production-secret-64chars
```

**.env.test** (test runner, commit this):
```
DATABASE_URL=postgres://postgres:postgres@localhost/myapp_test
SMTP_HOST=
FORGE_ENV=test
```

### Running in each environment

```bash
# development (default)
./app

# staging
FORGE_ENV=staging ./app

# production
FORGE_ENV=production ./app

# test
FORGE_ENV=test make test
```

### Checking env in code

```jda
forge_env()               // returns "development", "staging", "production", "test"
forge_env_is("production") // bool

if forge_env_is("production") {
    app_use(app, fn_addr(forge_rate_limit))
    app_use(app, fn_addr(forge_secure_headers))
}
```

---

## License

MIT
