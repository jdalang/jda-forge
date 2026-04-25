# Advanced Features

This page covers advanced capabilities built into Forge.

---

## Table of Contents

1. [ctx_head — status-only response](#1-ctx_head--status-only-response)
2. [Signed cookies](#2-signed-cookies)
3. [Pessimistic locking](#3-pessimistic-locking)
4. [ORM helpers: find_or_init_by and insert_all](#4-orm-helpers-find_or_init_by-and-insert_all)
5. [Text helpers: highlight and excerpt](#5-text-helpers-highlight-and-excerpt)
6. [Enum helpers](#6-enum-helpers)
7. [Current attributes](#7-current-attributes)
8. [Controller rescue handler](#8-controller-rescue-handler)
9. [Background jobs: delayed execution, backoff retry, discard_on, callbacks](#9-background-jobs)
10. [Mailer: delayed delivery and previews](#10-mailer-delayed-delivery-and-previews)
11. [Counter caches](#11-counter-caches)
12. [Dirty tracking](#12-dirty-tracking)
13. [Form builder with model binding](#13-form-builder-with-model-binding)
14. [Structured logging](#14-structured-logging)
15. [Instrumentation / event bus](#15-instrumentation--event-bus)
16. [Single Table Inheritance (STI)](#16-single-table-inheritance-sti)

---

## 1. ctx_head — status-only response

Send an HTTP response with a status code and no body. Useful for `HEAD` requests and API endpoints that confirm an action without returning data.

```jda
fn posts_check(ctx: i64) {
    let id = ctx_param(ctx, "id")
    let res = post_find(id)
    if res.count == 0 {
        ctx_head(ctx, 404)
        ret
    }
    ctx_head(ctx, 200)
}
```

`ctx_head` is equivalent to `ctx_respond(ctx, status, "", "")` — headers are still sent (including any you set before calling it), but the body is empty.

---

## 2. Signed cookies

`ctx_cookie_signed_set` writes a cookie whose value is signed with the application secret (`APP_SECRET` / `g_forge_cfg.secret_key`). `ctx_cookie_signed_get` verifies the signature and returns the value, or `""` if the cookie is missing, expired, or has been tampered with.

```jda
// Set a signed cookie that lasts 7 days
ctx_cookie_signed_set(ctx, "user_id", user_id, 604800)

// Read it back — "" means tampered or missing
let uid = ctx_cookie_signed_get(ctx, "user_id")
if uid.len == 0 {
    ctx_redirect(ctx, "/login")
    ret
}
```

The signature is a FNV-32a checksum mixed with the secret, encoded as 8 hex characters appended to the value with a `.` separator (`value.XXXXXXXX`). This prevents casual tampering but is not a cryptographic HMAC — do not store high-value secrets in signed cookies; use the session store for those.

`APP_SECRET` must be set in your `.env.*` file for signatures to be consistent across restarts.

---

## 3. Pessimistic locking

Chain `.lock()` onto any query to append `FOR UPDATE` to the generated SQL. Use inside a transaction to prevent concurrent modifications to the same row.

```jda
forge_begin()
let q = forge_q("accounts")
forge_q_where_eq(q, "id", account_id)
forge_q_lock(q)
let res = forge_q_exec(q)
let balance = forge_result_col(res, 0, "balance")
// ... deduct, update ...
let uq = forge_q("accounts")
forge_q_where_eq(uq, "id", account_id)
let ok = forge_q_update_all(uq, "balance = balance - 100")
if ok { forge_commit() } else { forge_rollback() }
```

`.lock()` has no effect outside of a transaction — most databases ignore `FOR UPDATE` without an active transaction.

**API:**

```jda
forge_q_lock(q: &ForgeQuery) -> &ForgeQuery
```

---

## 4. ORM helpers: find_or_init_by and insert_all

### forge_find_or_init_by

Look up a row by a single column. If found, return a `ForgeAttrs` pre-seeded with `id` and the lookup column. If not found, return a new `ForgeAttrs` with only the lookup column set (so you can fill in other fields and call `forge_attrs_insert`).

```jda
// Find or build a user by email
let a = forge_find_or_init_by("users", "email", "alice@example.com")
if forge_attrs_get(a, "id").len > 0 {
    // existing user — a.id is set
} else {
    // new user — set remaining fields then insert
    forge_attrs_set(a, "name", "Alice")
    forge_attrs_set(a, "role", "editor")
    forge_attrs_insert(a, "users")
}
```

### forge_insert_all

Bulk-insert multiple rows in a single SQL statement. You are responsible for SQL-escaping the values in `rows_csv`.

```jda
// Bulk insert three tags
let cols = "name, color"
let rows = "('ruby','red'),('go','cyan'),('jda','blue')"
forge_insert_all("tags", cols, rows)
```

`rows_csv` must be a valid SQL VALUES list — each tuple wrapped in parentheses, values properly single-quoted and escaped. Use `forge_db_escape_str` if values come from user input.

**Callbacks and validations do not run for `forge_insert_all`.** It is a raw batch insert for high-throughput seeding or migration scenarios.

---

## 5. Text helpers: highlight and excerpt

### forge_highlight

Wrap every case-insensitive match of `phrase` in str with an HTML element.

```jda
let html = forge_highlight("The quick brown fox", "quick", "mark")
// → "The <mark>quick</mark> brown fox"
```

The `tag_name` parameter is just the element name — the function generates `<tag>match</tag>`. Common choices: `"mark"`, `"em"`, `"strong"`.

```jda
fn posts_show(ctx: i64) {
    let q    = ctx_param(ctx, "q")
    let post = post_find(ctx_param(ctx, "id"))
    let body = forge_result_col(post, 0, "body")
    let highlighted = forge_highlight(body, q, "mark")
    // pass highlighted to view (use <%== %> — it's already HTML)
}
```

### forge_excerpt

Extract a short snippet around the first occurrence of `phrase`, with `"..."` added at the edges when the snippet is taken from the middle of the string.

```jda
let snip = forge_excerpt("The quick brown fox jumps over the lazy dog", "fox", 10)
// → "...brown fox jumps..."
```

If `phrase` is not found, the first `radius` characters of the string are returned.

```jda
let snip = forge_excerpt(body, search_term, 120)
ctx_render(ctx, view_search_result(ctx, snip))
```

---

## 6. Enum helpers

Forge does not auto-generate enum constants from the schema, but two utility functions make it easy to work with integer-coded enum columns stored in the database.

### forge_enum_val

Return the 0-based index of a name in a comma-separated list as a string. Returns `"-1"` when not found.

```jda
const POST_STATUSES = "draft,published,archived"

let val = forge_enum_val("published", POST_STATUSES)   // "1"
forge_q("posts").where_eq("status", val).exec()
```

### forge_enum_name

Return the name at a given 0-based index. Returns `""` when out of range.

```jda
let status_int = forge_result_col(res, 0, "status")   // "1"
let label = forge_enum_name(str_to_i64(status_int), POST_STATUSES)   // "published"
ctx_render(ctx, view_post_show(ctx, label))
```

**Pattern — declare constants once in the model file:**

```jda
const POST_STATUSES        = "draft,published,archived"
const POST_STATUS_DRAFT    = "0"
const POST_STATUS_PUBLISHED = "1"
const POST_STATUS_ARCHIVED = "2"

fn post_published_q() -> &ForgeQuery {
    ret forge_q("posts").where_eq("status", POST_STATUS_PUBLISHED)
}
```

---

## 7. Current attributes

Request-scoped key/value storage. Values are stored for the duration of a single request and are accessible from anywhere that has the `ctx` pointer — controllers, helpers, models called during the request.

```jda
// In a before filter — set the current user once
fn require_login(ctx: i64) {
    let uid = ctx_cookie_signed_get(ctx, "user_id")
    if uid.len == 0 { ctx_redirect(ctx, "/login")  ret }
    forge_current_set(ctx, "user_id", uid)
}

// In a controller action — read it back
fn posts_create(ctx: i64) {
    let uid = forge_current_get(ctx, "user_id")
    forge_attrs_set(forge_attrs_new(), "author_id", uid)
    // ...
}
```

**API:**

```jda
forge_current_set  (ctx: i64, key: []i8, val: []i8)
forge_current_get  (ctx: i64, key: []i8) -> []i8
forge_current_clear(ctx: i64, key: []i8)
```

Values are stored in the cache with a 30-second TTL using the composite key `"__cur_<ctx>_<key>"`. Do not use `forge_current_*` for values that must persist beyond a single request — use the session store for those.

---

## 8. Controller rescue handler

Register a fallback handler that's called when an action completes without sending any response. Use it to provide a consistent error page across an entire controller.

```jda
fn application_rescue(ctx: i64) {
    forge_log("ERROR: action completed without response — ctx=" + fmt_i64_s(ctx))
    ctx_internal_error(ctx, "Something went wrong")
}

fn posts_ctrl_init() -> &ForgeController {
    let ctrl = forge_ctrl_new()
    forge_ctrl_before(ctrl, fn_addr(require_login), "")
    forge_ctrl_rescue(ctrl, fn_addr(application_rescue))
    ret ctrl
}
```

The rescue handler receives the same `ctx: i64` as the action. It is only invoked when the action (and any before filters that ran) finished without calling `ctx_render`, `ctx_redirect`, `ctx_json_ok`, or any other response function.

**API:**

```jda
forge_ctrl_rescue(ctrl: &ForgeController, fn_ptr: i64)
```

---

## 9. Background jobs: delayed execution and backoff retry

### Delayed jobs — forge_job_enqueue_in

Enqueue a job to run after a delay. A lightweight goroutine sleeps the required time and then dispatches the job into the worker pool.

```jda
// Send a follow-up email 10 minutes after sign-up
forge_job_enqueue_in(fn_addr(send_followup_email), user_id as i64, 600000)
//                                                                 ^ delay in ms
```

The job function signature is the same as any other job:

```jda
fn send_followup_email(uid: i64) {
    let user = user_find(fmt_i64_s(uid))
    // ...
}
```

**API:**

```jda
forge_job_enqueue_in(fn_ptr: i64, arg: i64, delay_ms: i64)
```

### Retry with exponential backoff — forge_job_enqueue_retry_backoff

Like `forge_job_enqueue_retry` but doubles the sleep delay between each attempt.

```jda
// Try up to 5 times, starting with a 2-second delay (then 4s, 8s, 16s, 32s)
forge_job_enqueue_retry_backoff(fn_addr(send_webhook), payload as i64, 5, 2000)
```

The job function must return a non-zero i64 on success (the worker interprets 0 as failure and schedules a retry).

```jda
fn send_webhook(payload: i64) -> i64 {
    // ... attempt HTTP post ...
    if ok { ret 1 }
    ret 0
}
```

**API:**

```jda
forge_job_enqueue_retry_backoff(fn_ptr: i64, arg: i64, max_retries: i64, base_delay_ms: i64)
```

The delay between retries follows the sequence: `base_delay_ms`, `base_delay_ms * 2`, `base_delay_ms * 4`, … up to `max_retries` additional attempts.

### discard_on — forge_job_enqueue_retry_discard

Register a predicate that permanently drops the job instead of retrying when it returns non-zero.

```jda
fn should_discard_webhook(arg: i64) -> i64 {
    let p: &WebhookPayload = arg as &WebhookPayload
    if p.attempt > 10 { ret 1 }   // give up after 10 tries regardless
    ret 0
}

forge_job_enqueue_retry_discard(fn_addr(send_webhook), payload as i64, 5, fn_addr(should_discard_webhook))
```

**API:**

```jda
forge_job_enqueue_retry_discard(fn_ptr: i64, arg: i64, max_retries: i64, discard_fn: i64)
```

`discard_fn` receives the same `arg` as the job function. Return non-zero to discard, zero to allow retry.

### Job callbacks — forge_job_before_perform / forge_job_after_perform

Register global hooks that fire before and after every job execution. Useful for APM, logging, or injecting request context.

```jda
fn log_job_start(arg: i64) {
    forge_log_info("job started")
}

fn log_job_end(arg: i64) {
    forge_log_info("job finished")
}

// Register once at startup before forge_jobs_start
forge_job_before_perform(fn_addr(log_job_start))
forge_job_after_perform(fn_addr(log_job_end))
forge_jobs_start(4)
```

**API:**

```jda
forge_job_before_perform(fn_ptr: i64)
forge_job_after_perform(fn_ptr: i64)
```

Both hooks receive the job `arg` as their only argument. Up to 8 before and 8 after hooks can be registered.

---

## 10. Mailer: delayed delivery and previews

### Delayed delivery — forge_mail_send_in

Send a mail asynchronously after a delay (uses `forge_job_enqueue_in` internally).

```jda
// Send a welcome email 30 seconds after sign-up
forge_mail_send_in(ForgeMail {
    to:      user_email,
    from:    "no-reply@example.com",
    subject: "Welcome!",
    body:    "<h1>Hi!</h1>",
    html:    true
}, 30000)
```

**API:**

```jda
forge_mail_send_in(mail: ForgeMail, delay_ms: i64)
```

### Mailer previews

In development, browse rendered email HTML without actually sending anything. Register preview functions and mount the handler.

**1. Register preview functions** — in `app/mailers/`:

```jda
fn preview_welcome_email() -> i64 {
    let m: &ForgeMail = alloc_pages(1)
    m.to      = "preview@example.com"
    m.from    = "no-reply@example.com"
    m.subject = "Welcome to MyApp"
    m.body    = "<h1>Hi Alice!</h1><p>Thanks for joining.</p>"
    m.html    = true
    ret m as i64
}

fn mailer_previews_init() {
    forge_mail_preview_register("welcome", fn_addr(preview_welcome_email))
}
```

**2. Mount the handler** in `main.jda`:

```jda
app_get(app, "/_forge/mailers",      fn_addr(forge_mail_preview_handler))
app_get(app, "/_forge/mailers/:name", fn_addr(forge_mail_preview_handler))
```

**3. Browse:** open `http://localhost:8080/_forge/mailers` to see the list, click a name to see the HTML.

The handler returns 404 in any environment other than `development`.

---

## 11. Counter caches

Declare a counter cache once in the child model's `*_model_init`. Forge auto-increments on insert and auto-decrements on soft-delete.

```jda
fn comment_model_init() {
    forge_model("comments")
    forge_assoc_belongs_to("post", "posts", "post_id")
    forge_counter_cache("comments", "post_id", "posts", "comments_count")
    forge_field("body, author", FORGE_V_PRESENCE)
}
```

**Schema**: add `comments_count integer not null default 0` to the `posts` migration.

**Reading the count** — no extra query needed, it's already in the posts row:

```jda
let p = post_row(post, 0)
// p.comments_count is the denormalized count
```

**Re-sync from scratch** (after bulk import or data fix):

```jda
forge_counter_cache_reset("comments")
```

**API:**

```jda
forge_counter_cache(child_table: []i8, fk_col: []i8, parent_table: []i8, counter_col: []i8)
forge_counter_cache_reset(child_table: []i8)
```

---

## 12. Dirty tracking

Snapshot column values after loading, then compare against the current state before saving.

```jda
fn posts_edit(ctx: i64) {
    let id  = ctx_param(ctx, "id")
    let res = post_find(id)
    // Snapshot
    forge_dirty_load_result("posts", id, res, "title")
    forge_dirty_load_result("posts", id, res, "body")
    ctx_render(ctx, view_posts_edit(ctx, res))
}

fn posts_update(ctx: i64) {
    let id        = ctx_param(ctx, "id")
    let new_title = ctx_form(ctx, "title")
    let new_body  = ctx_form(ctx, "body")

    if forge_dirty_changed("posts", id, "title", new_title) {
        forge_log_info("title changed from: " + forge_dirty_was("posts", id, "title"))
    }

    // ... save ...
}
```

**API:**

```jda
forge_dirty_load_result(table: []i8, id: []i8, res: &ForgeResult, col: []i8)
forge_dirty_set        (table: []i8, id: []i8, col: []i8, orig_val: []i8)
forge_dirty_was        (table: []i8, id: []i8, col: []i8) -> []i8
forge_dirty_changed    (table: []i8, id: []i8, col: []i8, current: []i8) -> bool
```

Snapshots are stored in the cache with a 5-minute TTL and keyed as `__orig_<table>_<id>_<col>`.

---

## 13. Form builder with model binding

Convenience wrappers that combine a `<label>` and an input element inside a `<div class="field">`, pre-filled from a typed row struct field.

```html
<%# app/views/posts/_form.html.jda %>
<% fn render_post_form(action: []i8, method: []i8, p: &PostRow, tok: []i8, btn: []i8) %>
<%== forge_form_tag_open(action, method, tok) %>
<%== forge_field_tag         ("title",  "Title",  p.title) %>
<%== forge_textarea_field_tag("body",   "Body",   p.body, 8, 60) %>
<%== forge_field_tag         ("author", "Author", p.author) %>
<%== forge_submit_tag(btn) %>
<%== forge_form_tag_close() %>
```

**API:**

```jda
forge_field_tag         (col: []i8, label: []i8, current_val: []i8) -> []i8
forge_field_tag_type    (col: []i8, label: []i8, type_s: []i8, current_val: []i8) -> []i8
forge_textarea_field_tag(col: []i8, label: []i8, current_val: []i8, rows: i64, cols: i64) -> []i8
forge_select_field_tag  (col: []i8, label: []i8, options: []i8, current_val: []i8) -> []i8
```

Values are HTML-escaped by the underlying `forge_input_tag` / `forge_textarea_tag` calls. Use `<%== %>` when calling these from templates since they return already-complete HTML.

---

## 14. Structured logging

Add request context to every log line — request ID, method, and path — without repeating them manually.

```jda
fn posts_create(ctx: i64) {
    forge_log_ctx_info(ctx, "creating post")
    // → [INFO] [req-abc123] POST /posts creating post

    if not ok {
        forge_log_ctx_error(ctx, "validation failed: " + err)
    }
}
```

For non-request code, use tagged logging:

```jda
forge_log_tagged("mailer", FORGE_LOG_INFO, "sending welcome email to " + email)
// → [INFO] [mailer] sending welcome email to alice@example.com
```

**API:**

```jda
forge_log_ctx_debug(ctx: i64, msg: []i8)
forge_log_ctx_info (ctx: i64, msg: []i8)
forge_log_ctx_warn (ctx: i64, msg: []i8)
forge_log_ctx_error(ctx: i64, msg: []i8)

forge_log_tagged(tag: []i8, level: i64, msg: []i8)
```

Levels use the existing `FORGE_LOG_DEBUG/INFO/WARN/ERROR` constants and respect `forge_log_level_set`.

---

## 15. Instrumentation / event bus

Subscribe to named events anywhere in the app. Fire them from models, jobs, or middleware. Useful for APM, audit logging, or decoupling side effects.

```jda
// Subscribe at startup
forge_subscribe("user.created",  fn_addr(on_user_created))
forge_subscribe("post.published", fn_addr(on_post_published))

// Handler
fn on_user_created(payload: i64) {
    let user_id: &i8 = payload as &i8
    forge_log_info("new user: " + user_id[0..str_len(user_id)])
}

// Fire from a model callback or controller
forge_instrument("user.created", user_id_str as i64)
```

**API:**

```jda
forge_subscribe  (event: []i8, fn_ptr: i64)
forge_instrument (event: []i8, payload: i64)
```

`payload` is a raw `i64` — cast any pointer or value in. All subscribers registered for that exact event name are called synchronously in registration order. Up to 32 total subscriptions.

---

## 16. Single Table Inheritance (STI)

STI lets multiple model types share one database table, differentiated by a type column. One migration, one table, subtype-scoped query helpers generated automatically.

### Schema

Add a `type` column (or any name you choose) to the shared table:

```sql
-- migrate:up
CREATE TABLE vehicles (
    id         SERIAL PRIMARY KEY,
    type       VARCHAR(64) NOT NULL,
    make       VARCHAR(255),
    model      VARCHAR(255),
    horsepower INTEGER,
    payload_kg INTEGER,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);
```

### Model files

Create one model file per subtype. Call `forge_sti_subtype` instead of `forge_model` — it sets the table context to the parent so validators and callbacks bind to the shared table:

```jda
// app/models/car.jda
fn car_model_init() {
    forge_sti_subtype("vehicles", "type", "Car")
    forge_field("make, model", FORGE_V_PRESENCE)
}

// app/models/truck.jda
fn truck_model_init() {
    forge_sti_subtype("vehicles", "type", "Truck")
    forge_field("make, model, payload_kg", FORGE_V_PRESENCE)
}
```

Register both init functions in `main` just like ordinary models:

```jda
fn main() {
    car_model_init()
    truck_model_init()
    // ...
}
```

### Generated helpers

`forge compile-models` detects the `forge_sti_subtype` declarations and emits a full set of scoped query functions for each subtype. All queries automatically include `WHERE type = '<TypeValue>'`.

| Generated function | Equivalent SQL |
|---|---|
| `car_all()` | `SELECT * FROM vehicles WHERE type='Car' ORDER BY created_at DESC` |
| `car_find(id)` | `SELECT * FROM vehicles WHERE id=? AND type='Car' LIMIT 1` |
| `car_find_by(col, val)` | `SELECT * FROM vehicles WHERE col=? AND type='Car' LIMIT 1` |
| `car_where(col, val)` | Returns a `ForgeQuery` pre-filtered for Cars |
| `car_q()` | Returns a bare `ForgeQuery` pre-filtered for Cars |
| `car_count()` | `SELECT COUNT(*) FROM vehicles WHERE type='Car'` |
| `car_exists(id)` | Existence check within Cars |
| `car_create_from(attrs)` | INSERT with type='Car' stamped automatically |
| `car_delete(id)` | Soft-delete on the shared table |
| `car_destroy(id)` | Hard-delete on the shared table |
| `car_touch(id)` | UPDATE updated_at on the shared table |
| `car_update_column(id, col, val)` | Single-column update on the shared table |
| `car_row(result, r)` | Returns `&VehicleRow` — delegates to `vehicle_row` |

If the parent table has a `deleted_at` column, `car_all`, `car_find`, etc. automatically exclude soft-deleted rows, and `car_with_deleted()` / `car_only_deleted()` are also generated.

### Usage in a controller

```jda
fn cars_index(ctx: i64) {
    let cars = car_all()
    ctx_render(ctx, 200, "cars/index", cars)
}

fn cars_create(ctx: i64) {
    let attrs = ctx_permit(ctx, "make, model, horsepower")
    if !car_create_from(attrs) {
        ctx_render(ctx, 422, "cars/new", 0)
        ret
    }
    ctx_redirect(ctx, "/cars")
}

fn cars_show(ctx: i64) {
    let id = ctx_param(ctx, "id")
    let car = car_find(id)
    if forge_result_empty(car) {
        ctx_head(ctx, 404)
        ret
    }
    ctx_render(ctx, 200, "cars/show", car)
}
```

### Row struct reuse

STI subtypes share the parent's row struct — `car_row` is a thin alias for `vehicle_row` and returns a `&VehicleRow`. No separate struct is generated, so all subtype accessors use the same field names.

---

## Summary table

| Feature | Function(s) |
|---|---|
| Status-only response | `ctx_head(ctx, status)` |
| Signed cookies | `ctx_cookie_signed_set`, `ctx_cookie_signed_get` |
| Pessimistic locking | `.lock()` on any `ForgeQuery` |
| Find or build | `forge_find_or_init_by(table, col, val)` |
| Bulk insert | `forge_insert_all(table, cols_csv, rows_csv)` |
| Highlight text | `forge_highlight(s, phrase, tag_name)` |
| Excerpt text | `forge_excerpt(s, phrase, radius)` |
| Enum index → name | `forge_enum_name(idx, vals_csv)` |
| Enum name → index | `forge_enum_val(name, vals_csv)` |
| Request-scoped store | `forge_current_set/get/clear(ctx, key, val)` |
| Controller fallback | `forge_ctrl_rescue(ctrl, fn_ptr)` |
| Delayed job | `forge_job_enqueue_in(fn_ptr, arg, delay_ms)` |
| Backoff retry | `forge_job_enqueue_retry_backoff(fn_ptr, arg, n, base_ms)` |
| discard_on | `forge_job_enqueue_retry_discard(fn_ptr, arg, n, discard_fn)` |
| Job callbacks | `forge_job_before_perform`, `forge_job_after_perform` |
| Delayed mailer | `forge_mail_send_in(mail, delay_ms)` |
| Mailer previews | `forge_mail_preview_register`, `forge_mail_preview_handler` |
| Counter caches | `forge_counter_cache(child, fk, parent, col)` |
| Dirty tracking | `forge_dirty_load_result`, `forge_dirty_was`, `forge_dirty_changed` |
| Form binding | `forge_field_tag`, `forge_textarea_field_tag`, `forge_select_field_tag` |
| Structured logging | `forge_log_ctx_info/warn/error/debug`, `forge_log_tagged` |
| Instrumentation | `forge_subscribe(event, fn_ptr)`, `forge_instrument(event, payload)` |
| STI subtypes | `forge_sti_subtype(parent, col, val)` in model init; `<sub>_all/find/create_from/...` generated |
