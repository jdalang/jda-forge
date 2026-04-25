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
      posts_controller.jda         # 7 thin action functions + rescue + after filter
      comments_controller.jda      # create + delete actions
    mailers/
      post_mailer.jda              # new-post notification + development preview
    models/
      post.jda                     # validations, callbacks, counter cache, instrumentation
      comment.jda                  # validations + counter cache declaration
    views/
      layouts/
        application.html.jda       # tmpl_layout
        _flash.html.jda            # tmpl_flash partial
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
      003_add_comments_count_to_posts.sql  # counter cache column
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

| Method | Path | File function | Compiled as | Description |
|---|---|---|---|---|
| GET | `/` | root | — | Redirects to `/posts` |
| GET | `/posts` | `fn index` | `posts_index` | List posts |
| GET | `/posts/new` | `fn new` | `posts_new` | New post form |
| POST | `/posts` | `fn create` | `posts_create` | Create post |
| GET | `/posts/:id` | `fn show` | `posts_show` | Show post + comments |
| GET | `/posts/:id/edit` | `fn edit` | `posts_edit` | Edit form |
| PUT | `/posts/:id` | `fn update` | `posts_update` | Update post |
| DELETE | `/posts/:id` | `fn delete` | `posts_delete` | Soft-delete post |
| POST | `/posts/:post_id/comments` | `fn create` | `comments_create` | Add comment |
| DELETE | `/posts/:post_id/comments/:id` | `fn delete` | `comments_delete` | Remove comment |

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

## app/models/post.jda — associations, callbacks, counter cache, instrumentation

`post_q`, `post_all`, `post_find`, `post_create`, `post_update`, `post_delete`, `post_comments`, etc. are all auto-generated into `_build/models.jda` — CRUD from the migration schema, association accessors from the `forge_assoc_*` declarations. The model file only contains what you write:

```jda
fn post_before_save(id: []i8) {
    if forge_dirty_changed("posts", id, "title", forge_fa_get("title")) {
        forge_log_tagged("post", FORGE_LOG_INFO, "title changed")
    }
}

fn post_after_create(id: []i8) {
    forge_instrument("post.created", id as i64)
}

fn post_model_init() {
    forge_model("posts")
    forge_assoc_has_many("comments", "comments", "post_id")
    forge_counter_cache ("comments", "post_id", "posts", "comments_count")
    forge_callback(FORGE_CB_BEFORE_SAVE,  fn_addr(post_before_save))
    forge_callback(FORGE_CB_AFTER_CREATE, fn_addr(post_after_create))
    forge_field       ("title, body, author", FORGE_V_PRESENCE)
    forge_field_length("title",               2, 255)
    forge_field_min   ("body",                10)
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

Action functions use bare names. `forge compile-routes` reads the filename (`posts_controller.jda`) to determine the controller is `posts`, then renames `fn create` to `fn posts_create` in the generated output — no naming conflicts across controllers, no prefix boilerplate to write.

```jda
fn create(ctx: i64) {
    let attrs = ctx_permit(ctx, "title, body, author")
    if post_create_from(attrs) {
        forge_log_ctx_info(ctx, "post created")
        ctx_flash_set(ctx, "notice", "Post created.")
        ctx_redirect(ctx, posts_path)
        ret
    }
    ctx_save_errors(ctx)
    ctx_redirect(ctx, new_post_path)
}
```

Filter helpers and rescue handlers are written the same way — bare names, prefixed automatically:

```jda
fn set_post(ctx: i64) { ... }    // compile-routes → fn posts_set_post
fn rescue(ctx: i64)   { ... }    // compile-routes → fn posts_rescue
fn log_action(ctx: i64) { ... }  // compile-routes → fn posts_log_action
```

`fn_addr()` references inside the same file are rewritten too, so `posts_before_actions` can use bare names:

```jda
forge_ctrl_before(ctrl, fn_addr(set_post),   "show, edit, update, delete")
forge_ctrl_after (ctrl, fn_addr(log_action), "")
forge_ctrl_rescue(ctrl, fn_addr(rescue))
```

Validations are declared once in `post_model_init` and fire automatically inside `post_create_from`. After a successful create, `FORGE_CB_AFTER_CREATE` fires `post_after_create` which calls `forge_instrument("post.created", id)`. The subscriber in `main.jda` sends the notification email asynchronously.

---

## app/views/posts/index.html.jda — ERB template

```html
<% fn view_posts_index(ctx: i64, posts: &ForgeResult) %>
<%layout "Posts" %>
<%== tmpl_flash(ctx) %>
<h1>Blog Posts</h1>
<a href="<%== new_post_path %>">New Post</a>
<hr>
<% if posts.count == 0 { %>
<p>No posts yet. <a href="<%== new_post_path %>">Write the first one.</a></p>
<% } %>
<% loop r in 0..posts.count { %>
<%== tmpl_post_row(post_row(posts, r)) %>
<% } %>
```

`forge compile-views` compiles this into a JDA function in `_build/views.jda`. Controllers call `ctx_render(ctx, view_posts_index(ctx, posts))` — the compiled function signature matches exactly.

- `<%= expr %>` — HTML-escapes user content via `forge_h(expr)`
- `<%== expr %>` — emits raw HTML (paths, partial calls, pre-built HTML)
- `<%layout "Posts" %>` — wraps the output in `tmpl_layout("Posts", buf.done())`

Partials receive typed row structs generated by `compile_models`. `post_row(posts, r)` converts a result row into a `&PostRow` with named fields:

```html
<%# app/views/posts/_post.html.jda %>
<% fn tmpl_post_row(post: &PostRow) %>
<div class="post">
  <h2><a href="<%== post_path(post.id) %>"><%= post.title %></a></h2>
  <p class="meta">by <%= post.author %> on <%== post.created_at %></p>
</div>
```

```html
<%# caller — passes row object, not individual fields %>
<% loop r in 0..posts.count { %>
<%== tmpl_post_row(post_row(posts, r)) %>
<% } %>
```

In show/edit views, convert the single-row result at the top:

```html
<% let p = post_row(post, 0) %>
<%layout p.title %>
<h1><%= p.title %></h1>
```

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

## Middleware stack and startup (main.jda)

```jda
forge_jobs_start(4)
forge_job_before_perform(fn_addr(on_job_before))  // job lifecycle hooks
forge_job_after_perform (fn_addr(on_job_after))

forge_migration_run("db/migrate")   // apply pending migrations at startup

app_use(app, fn_addr(forge_logger))         // request log
app_use(app, fn_addr(forge_request_id))     // X-Request-Id header
app_use(app, fn_addr(forge_secure_headers)) // HSTS, X-Frame-Options, CSP
app_use(app, fn_addr(forge_session_start))  // cookie session (required for flash + CSRF)
app_use(app, fn_addr(forge_csrf))           // block forged POST/PUT/DELETE

// Subscribe the mailer to the post.created instrumentation event.
forge_subscribe("post.created", fn_addr(post_mailer_new_post))

// Register mailer previews (dev-only: /_forge/mailers).
forge_mail_preview_register("new_post", fn_addr(post_mailer_preview_new_post))
```

---

## Build pipeline

The Makefile uses `find` to recursively discover all `.jda` files under `app/`, merges them in dependency order, and concatenates into `_build/blog.jda`:

```makefile
CONFIG      = config/application.jda
HELPERS     = $(shell find app/helpers     -name "*.jda"      2>/dev/null | sort)
MODELS      = $(shell find app/models      -name "*.jda"      2>/dev/null | sort)
MAILERS     = $(shell find app/mailers     -name "*.jda"      2>/dev/null | sort)
CONTROLLERS = $(shell find app/controllers -name "*.jda"      2>/dev/null | sort)
ROUTES      = _build/routes.jda       # compiled from config/routes.jda
CTRL_INIT   = _build/controllers.jda  # scanned from app/controllers/
MODELS_GEN  = _build/models.jda       # typed structs + CRUD (from compile-models)
VIEWS_GEN   = _build/views.jda        # compiled .html.jda templates
MAIN        = main.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS_GEN) $(VIEWS_GEN) $(MODELS) $(MAILERS) $(CONTROLLERS) $(CTRL_INIT) $(ROUTES) $(MAIN)

_gen:
    @forge compile-routes
    @forge compile-models
    @forge compile-views

build: _gen $(OUT)
    jda build --include libs/forge.jda $(OUT) -o blog
```

Order matters: `config/application.jda` first (constants and `load_env`), then helpers, models, views, controllers, generated init + routes (from `_build/`), and finally `main.jda` which calls `forge_controllers_init()`, `routes(app)`, and starts the server. The `_gen` target runs `forge compile-routes` before every build to regenerate those `_build/` files.

---

## Counter cache — comments_count

Migration `003_add_comments_count_to_posts.sql` adds a `comments_count` column:

```sql
ALTER TABLE posts ADD COLUMN comments_count INTEGER NOT NULL DEFAULT 0;
```

The `comment_model_init` declares the counter cache:

```jda
forge_counter_cache("comments", "post_id", "posts", "comments_count")
```

Forge now increments/decrements `comments_count` automatically on every comment create and soft-delete. The post partial uses it directly — no extra query:

```jda
<p class="meta">... <%== post.comments_count %> comment(s)</p>
```

---

## Dirty tracking in the update action

`posts_controller.jda` snapshots the original title before the update and logs only when it actually changes:

```jda
fn set_post(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    forge_dirty_load_result("posts", id, post, "title")  // snapshot
    ctx_set(ctx, "post", post as i64)
}

fn update(ctx: i64) {
    let id = ctx_param(ctx, "id")
    if post_update_from(id, ctx_permit(ctx, "title, body, author")) {
        if forge_dirty_changed("posts", id, "title", ctx_param(ctx, "title")) {
            forge_log_ctx_info(ctx, "post title was changed")
        }
        // ...
    }
}
```

---

## Instrumentation — post.created event

`post_after_create` fires an instrumentation event with the new post's id:

```jda
fn post_after_create(id: []i8) {
    forge_instrument("post.created", id as i64)
}
```

`main.jda` subscribes the mailer to that event:

```jda
forge_subscribe("post.created", fn_addr(post_mailer_new_post))
```

This decouples the mailer from the controller and the model — either can be changed or replaced without touching the other.

---

## Mailer — post_mailer.jda

`app/mailers/post_mailer.jda` defines a notification mailer and a preview:

```jda
fn post_mailer_new_post(post_id_raw: i64) {
    let post = post_find(post_id_raw as []i8)
    let p    = post_row(post, 0)
    let mail: ForgeMail
    mail.to      = forge_env_get("NOTIFY_EMAIL")
    mail.from    = forge_env_get("MAIL_FROM")
    mail.subject = forge_str_concat("New post: ", p.title)
    mail.body    = forge_str_concat("A new post has been published by ", p.author)
    forge_mail_send_async(mail)
}

fn post_mailer_preview_new_post() -> ForgeMail { ... }
```

Browse the preview at `/_forge/mailers/new_post` in development.

---

## After action filter + rescue handler

`posts_controller.jda` wires up a per-controller after filter and rescue handler:

```jda
fn posts_before_actions() {
    let ctrl = forge_ctrl_new()
    forge_ctrl_before (ctrl, fn_addr(set_post),   "show, edit, update, delete")
    forge_ctrl_after  (ctrl, fn_addr(log_action), "")
    forge_ctrl_rescue (ctrl, fn_addr(rescue))
    forge_ctrl_register("posts", ctrl)
}
```

`posts_log_action` logs every completed request; `posts_rescue` renders a 500 page if an action exits without sending a response.

---

## Form builder

`_form.html.jda` now uses the `forge_field_tag` / `forge_textarea_field_tag` helpers instead of raw `<input>` and `<label>` HTML:

```jda
<%== forge_field_tag("title", "Title", title_val) %>
<%== forge_textarea_field_tag("body", "Body", body_val, 10, 60) %>
<%== forge_field_tag("author", "Author", "") %>
```

Each helper emits a `<div class="field">` wrapping a `<label>` and the input, with values HTML-escaped automatically.

---

## Structured logging

Controllers use `forge_log_ctx_info` / `forge_log_ctx_error` so every log line carries the request ID and method/path prefix:

```
[req-abc123] POST /posts  post created
[req-abc123] DELETE /posts/1  post deleted
```

`forge_log_tagged` is used in the model for context-free log lines:

```jda
forge_log_tagged("post", FORGE_LOG_INFO, "title changed")
// → [post] title changed
```

---

## Job lifecycle hooks (main.jda)

Two hooks log around every background job execution:

```jda
forge_job_before_perform(fn_addr(on_job_before))
forge_job_after_perform (fn_addr(on_job_after))
```

This makes it easy to add APM tracing or request-scoped state resets without modifying individual job functions.
