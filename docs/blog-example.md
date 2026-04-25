# Blog Example App

**Location:** [`examples/blog/`](../examples/blog/)

A complete multi-file Forge application demonstrating:

- Posts and comments CRUD
- Sessions, flash messages, CSRF protection
- Model validations and soft delete
- Multi-environment configuration (development / staging / production / test)
- Database migrations
- Rails-style MVC directory layout
- Chainable request tests

---

## File Layout

```
examples/blog/
  Forgefile                         # dependency declaration (pinned to forge v3.0.0)
  Forgefile.lock                    # exact resolved versions (commit this)
  Makefile                          # build pipeline
  main.jda                          # app wiring
  .env                              # FORGE_ENV=development, APP_PORT=8080
  .env.example                      # template — copy per environment
  app/
    controllers/
      application_controller.jda   # require_login, current_user_id
      posts_controller.jda         # 7 thin action functions
      comments_controller.jda      # create + delete actions
    models/
      post.jda                     # validations + custom scopes (CRUD auto-generated)
      comment.jda                  # validations + custom scopes (CRUD auto-generated)
    views/
      layouts/
        application.html.jda       # tmpl_layout, tmpl_flash
      posts/
        index.html.jda             # view_posts_index
        show.html.jda              # view_posts_show
        new.html.jda               # view_posts_new
        edit.html.jda              # view_posts_edit
        _post.html.jda             # tmpl_post_row partial
        _form.html.jda             # render_post_form partial
      comments/
        _comment.html.jda          # tmpl_comment_row partial
      shared/
        _errors.html.jda           # render_errors partial
    helpers/
      application_helper.jda       # h(), link_to(), pluralize()
  config/
    application.jda                # load_env() + app_config()
    routes.jda                     # routes DSL — edit this, never _build/routes.jda
    environments/
      development.jda
      test.jda
      production.jda
  db/
    migrate/
      001_create_posts.sql         # posts table with indexes
      002_create_comments.sql      # comments table with FK to posts
    seeds.jda                      # db_seed()
  test/
    test_posts.jda                 # chainable request tests
  public/                          # static assets
```

---

## Running the app

```bash
cd examples/blog
forge install                          # downloads forge.jda into libs/
cp .env.example .env.development
# edit .env.development — set DATABASE_URL, APP_SECRET
forge server                           # build + start on :8080
```

---

## Routes

| Method | Path | Action | Description |
|---|---|---|---|
| GET | `/` | root | Redirects to `/posts` |
| GET | `/posts` | `posts_index` | List posts |
| GET | `/posts/new` | `posts_new` | New post form |
| POST | `/posts` | `posts_create` | Create post |
| GET | `/posts/:id` | `posts_show` | Show post + comments |
| GET | `/posts/:id/edit` | `posts_edit` | Edit form |
| PUT | `/posts/:id` | `posts_update` | Update post |
| DELETE | `/posts/:id` | `posts_delete` | Soft-delete post |
| POST | `/posts/:post_id/comments` | `comments_create` | Add comment |
| DELETE | `/posts/:post_id/comments/:id` | `comments_delete` | Remove comment |

---

## config/application.jda — environment loading

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

## config/routes.jda — routes DSL

The only routing file you edit:

```
root "posts#index"

resources "posts" do
  resources "comments"
end
```

`forge build` compiles this into `_build/routes.jda` (path helpers + `routes()` function) and scans `app/controllers/*.jda` to produce `_build/controllers.jda`. You never edit either generated file.

Path helpers available everywhere in the app after build:

```jda
posts_path                              // "/posts"
new_post_path                           // "/posts/new"
post_path(id)                           // "/posts/42"
edit_post_path(id)                      // "/posts/42/edit"
post_comments_path(post_id)             // "/posts/42/comments"
post_comment_path(post_id, id)          // "/posts/42/comments/7"
```

---

## app/models/post.jda — validations + custom scopes

`post_q`, `post_all`, `post_find`, `post_create`, `post_update`, `post_delete`, etc. are auto-generated into `_build/models.jda` from the migration. The model file only contains what you write:

```jda
// Custom scopes
fn post_published() -> &ForgeResult {
    ret forge_q("posts").where_eq("published", "true").order_desc("created_at").exec()
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

// Custom action
fn post_publish(id: []i8) -> bool {
    ret forge_q("posts").where_eq("id", id).update_all("published = true, updated_at = NOW()")
}
```

`forge_q("posts")` automatically excludes rows where `deleted_at IS NOT NULL`. Chain anything off `post_q()`:

```jda
let res = post_q()
    .where_ilike("title", "%jda%")
    .left_join("users", "users.id = posts.user_id")
    .order_desc("created_at")
    .page(2, 20)
    .exec()
```

---

## app/controllers/posts_controller.jda — thin actions

```jda
fn posts_create(ctx: i64) {
    let title  = ctx_form(ctx, "title")
    let body   = ctx_form(ctx, "body")
    let author = ctx_form(ctx, "author")

    let errs = post_validate(title, body, author)
    if forge_errors_any(errs) {
        ctx_flash_set(ctx, "alert", forge_errors_json(errs))
        ctx_redirect(ctx, new_post_path)
        ret
    }

    if !post_create(title, body, author) {
        ctx_flash_set(ctx, "alert", "Could not save post.")
        ctx_redirect(ctx, new_post_path)
        ret
    }

    ctx_flash_set(ctx, "notice", "Post created.")
    ctx_redirect(ctx, posts_path)
}
```

Pattern: validate → flash error + redirect on failure → flash success + redirect on success.

Controllers use path helper constants (`posts_path`, `new_post_path`) rather than hard-coded strings.

---

## app/views/posts/index.html.jda — view function

```jda
fn view_posts_index(posts: &ForgeResult) -> []i8 {
    let buf = forge_buf_new(8)
    buf.write("<h1>Posts</h1>")
       .write(link_to("New Post", new_post_path, "button"))
       .write("<ul>")
    loop r in 0..posts.count {
        buf.write(tmpl_post_row(posts, r))
    }
    buf.write("</ul>")
    ret tmpl_layout("Posts", buf.done())
}
```

View functions return `[]i8` (a string). Controllers call them via `ctx_render(ctx, view_posts_index(posts))`. `ForgeBuf` eliminates manual loop-copy boilerplate — `buf.write(s)` returns `&ForgeBuf` so calls chain.

---

## test/test_posts.jda — chainable request tests

```jda
fn test_setup() {
    forge_exec_sql("DELETE FROM posts")
    forge_exec_sql("INSERT INTO posts (title, body, author) VALUES ('Test', 'Body text here', 'Alice')")
}

fn test_posts_index() {
    test_setup()
    forge_get(posts_path).ok(200).has("Test")
}

fn test_post_create_valid() {
    let body = "title=Hello+World&body=This+is+a+test+post+body&author=Alice"
    forge_post(posts_path, body).redirect()
}

fn test_post_create_missing_title() {
    forge_post(posts_path, "title=&body=Some+body+text&author=Alice").redirect()
}

fn test_post_not_found() {
    forge_get(post_path("99999")).ok(404)
}

fn test_post_delete() {
    forge_delete(post_path("1")).redirect()
}
```

Run tests:

```bash
forge test               # FORGE_ENV=test ./test_runner
```

In test mode (`FORGE_ENV=test`):
- SMTP is disabled — emails are captured in memory, never sent
- `forge_get/post/put/delete` drive requests through the real router without opening a socket
- CSRF tokens are included automatically on POST/PUT/DELETE
- Database uses `DATABASE_URL` from `.env.test`

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

The Makefile uses `find` to recursively discover all `.jda` files under `app/`, merges them in dependency order, and concatenates into `_build/blog.jda`:

```makefile
CONFIG      = config/application.jda
HELPERS     = $(shell find app/helpers     -name "*.jda"      2>/dev/null | sort)
MODELS      = $(shell find app/models      -name "*.jda"      2>/dev/null | sort)
VIEWS       = $(shell find app/views       -name "*.html.jda" 2>/dev/null | sort)
CONTROLLERS = $(shell find app/controllers -name "*.jda"      2>/dev/null | sort)
ROUTES      = _build/routes.jda       # compiled from config/routes.jda
CTRL_INIT   = _build/controllers.jda  # scanned from app/controllers/
MAIN        = main.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS) $(VIEWS) $(CONTROLLERS) $(CTRL_INIT) $(ROUTES) $(MAIN)

_gen:
    @forge compile-routes

build: _gen $(OUT)
    jda build --include libs/forge.jda $(OUT) -o blog
```

Order matters: `config/application.jda` first (constants and `load_env`), then helpers, models, views, controllers, generated init + routes (from `_build/`), and finally `main.jda` which calls `forge_controllers_init()`, `routes(app)`, and starts the server. The `_gen` target runs `forge compile-routes` before every build to regenerate those `_build/` files.
