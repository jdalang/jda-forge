# Blog Example App

**Location:** [`examples/blog/`](../examples/blog/)

A complete multi-file Forge application demonstrating:

- Posts and comments CRUD
- Sessions, flash messages, CSRF protection
- Model validations and soft delete
- Multi-environment configuration (development / staging / production / test)
- Database migrations
- Request tests

---

## File Layout

```
examples/blog/
  Forgefile                    # dependency declaration (pinned to forge v3.0.0)
  Forgefile.lock               # exact resolved versions (commit this)
  Makefile                     # build pipeline
  config.jda                   # load_env() + app_config()
  .env                         # FORGE_ENV=development, APP_PORT=8080
  .env.example                 # template — copy per environment
  db/
    migrations/
      001_create_posts.sql     # posts table with indexes
      002_create_comments.sql  # comments table with FK to posts
  models/
    post.jda                   # validations, finders, create/update/delete/publish
    comment.jda                # validations, finders, create/delete
  views/
    templates.jda              # layout(), flash(), post_row(), comment_row()
  routes/
    posts.jda                  # all 7 post handlers + register_post_routes()
    comments.jda               # create + delete handlers + register_comment_routes()
  test/
    test_blog.jda              # 8 test cases
  main.jda                     # app wiring
```

---

## Running the app

```bash
cd examples/blog
forge install                          # downloads forge.jda into libs/
cp .env.example .env.development
# edit .env.development — set DATABASE_URL, APP_SECRET
forge server                               # build + start on :8080
```

---

## Routes

| Method | Path | Handler | Description |
|---|---|---|---|
| GET | `/` | redirect | Redirects to `/posts` |
| GET | `/posts` | `handle_posts_index` | List published posts |
| GET | `/posts/new` | `handle_posts_new` | New post form |
| POST | `/posts` | `handle_posts_create` | Create post |
| GET | `/posts/:id` | `handle_posts_show` | Show post + comments |
| GET | `/posts/:id/edit` | `handle_posts_edit` | Edit form |
| POST | `/posts/:id` | `handle_posts_update` | Update post |
| DELETE | `/posts/:id` | `handle_posts_delete` | Soft-delete post |
| POST | `/posts/:post_id/comments` | `handle_comments_create` | Add comment |
| DELETE | `/posts/:post_id/comments/:id` | `handle_comments_delete` | Remove comment |

---

## config.jda — environment loading

```jda
fn load_env() {
    let env = forge_env_get("FORGE_ENV")
    if env.len == 0 { env = "development" }
    forge_dotenv_load(".env")
    if str_eq(env, "development") { forge_dotenv_load(".env.development") }
    else if str_eq(env, "staging")    { forge_dotenv_load(".env.staging")    }
    else if str_eq(env, "production") { forge_dotenv_load(".env.production") }
    else if str_eq(env, "test")       { forge_dotenv_load(".env.test")       }
}

fn app_config() -> ForgeConfig {
    let cfg = forge_default_config()
    cfg.db_url     = forge_env_get("DATABASE_URL")
    cfg.smtp_host  = forge_env_get("SMTP_HOST")
    cfg.secret_key = forge_env_get("APP_SECRET")
    if forge_env_is("test") || forge_env_is("development") { cfg.smtp_host = "" }
    if forge_env_is("development") { forge_log_level_set(FORGE_LOG_DEBUG) }
    else                           { forge_log_level_set(FORGE_LOG_INFO)  }
    ret cfg
}
```

`.env` files per environment:

| File | Purpose | Commit? |
|---|---|---|
| `.env` | Shared defaults | Yes |
| `.env.development` | Local dev values | No |
| `.env.staging` | Staging server | No |
| `.env.production` | Production server | No |
| `.env.test` | Test runner | Yes (no secrets) |

---

## models/post.jda — query interface + validation + soft delete

```jda
// Rails AR-style query interface
fn post_q() -> &ForgeQuery { ret forge_q("posts") }
fn post_all() -> &ForgeResult {
    ret forge_q("posts").order_desc("created_at").exec()
}
fn post_published() -> &ForgeResult {
    ret forge_q("posts").where_eq("published", "true").order_desc("created_at").exec()
}
fn post_count() -> i64    { ret forge_q("posts").count() }
fn post_exists(id: []i8) -> bool {
    ret forge_q("posts").where_eq("id", id).exists()
}

// Validations
fn post_validate(title: []i8, body: []i8, author: []i8) -> &ForgeErrors {
    let e = forge_errors_new()
    forge_validate_presence  (e, "title",  title)
    forge_validate_length    (e, "title",  title,  2, 255)
    forge_validate_presence  (e, "body",   body)
    forge_validate_min_length(e, "body",   body,   10)
    forge_validate_presence  (e, "author", author)
    ret e
}

fn post_delete(id: []i8) -> bool {
    ret forge_soft_delete("posts", id)   // sets deleted_at, excluded from queries
}
```

`forge_q("posts")` automatically excludes rows where `deleted_at IS NOT NULL`.

Chain anything off `post_q()`:

```jda
let res = post_q()
    .where_ilike("title", "%jda%")
    .left_join("users", "users.id = posts.user_id")
    .order_desc("created_at")
    .page(2, 20)
    .exec()
```

---

## routes/posts.jda — create handler

```jda
fn handle_posts_create(ctx: i64) {
    let title  = ctx_form(ctx, "title")
    let body   = ctx_form(ctx, "body")
    let author = ctx_form(ctx, "author")

    let errs = post_validate(title, body, author)
    if forge_errors_any(errs) {
        ctx_flash_set(ctx, "alert", forge_errors_json(errs))
        ctx_redirect(ctx, "/posts/new")
        ret
    }

    if !post_create(title, body, author) {
        ctx_flash_set(ctx, "alert", "Could not save post.")
        ctx_redirect(ctx, "/posts/new")
        ret
    }

    ctx_flash_set(ctx, "notice", "Post created.")
    ctx_redirect(ctx, "/posts")
}
```

Pattern: validate → flash error + redirect on failure → flash success + redirect on success.

---

## test/test_blog.jda — request tests

```jda
fn test_post_create_valid() {
    let body = "title=Hello+World&body=This+is+a+test+post+body&author=Alice"
    let res  = forge_test_post("/posts", body)
    forge_assert_redirect(res)
}

fn test_post_create_missing_title() {
    let body = "title=&body=Some+body+text&author=Alice"
    let res  = forge_test_post("/posts", body)
    forge_assert_redirect(res)   // redirects back to /posts/new with flash
}

fn test_post_show_not_found() {
    let res = forge_test_get("/posts/99999")
    forge_assert_status(res, 404)
}
```

Run tests:

```bash
forge test               # FORGE_ENV=test ./test_runner
```

In test mode (`FORGE_ENV=test`):
- SMTP is disabled
- `forge_test_get/post/delete` drive requests through the real router without opening a socket
- Responses are captured in memory

---

## Middleware stack (main.jda)

```jda
app_use(app, fn_addr(forge_logger))         // request log
app_use(app, fn_addr(forge_request_id))     // X-Request-Id header
app_use(app, fn_addr(forge_secure_headers)) // HSTS, X-Frame-Options, CSP
app_use(app, fn_addr(forge_session_start))  // cookie session (required for flash + CSRF)
app_use(app, fn_addr(forge_csrf))           // block forged POST/PUT/DELETE
```

---

## Build pipeline

The Makefile concatenates all source files into `_build/blog.jda`, then compiles:

```makefile
SRC = config.jda $(wildcard models/*.jda) $(wildcard views/*.jda) \
      $(wildcard routes/*.jda) main.jda

$(OUT): $(SRC)
    cat $(SRC) > $(OUT)

build: $(OUT)
    jda build --include libs/forge.jda $(OUT) -o blog
```

Order matters: `config.jda` first (constants and `load_env`), then models, views, routes, and finally `main.jda` which wires everything together.
