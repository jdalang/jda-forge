# Models

The Forge model layer provides database access, querying, validation, associations, callbacks, and migrations for JDA applications. It follows an Active Record style: each database table has a corresponding set of generated functions that handle common operations, and a chainable query builder handles everything else.

---

## Table of Contents

1. [Generating a Model](#generating-a-model)
2. [Generated Query Interface](#generated-query-interface)
3. [Query Builder Reference](#query-builder-reference)
   - [Constructor](#constructor)
   - [Column Selection](#column-selection)
   - [WHERE Conditions](#where-conditions)
   - [OR Conditions](#or-conditions)
   - [JOINs](#joins)
   - [Grouping and HAVING](#grouping-and-having)
   - [Ordering](#ordering)
   - [Pagination and Limits](#pagination-and-limits)
   - [Execution](#execution)
   - [Aggregates](#aggregates)
   - [DML: Bulk Update and Delete](#dml-bulk-update-and-delete)
4. [Named Scopes](#named-scopes)
5. [Batch Processing](#batch-processing)
6. [Validations](#validations)
7. [Associations](#associations)
8. [Callbacks](#callbacks)
9. [Before Actions (Controller Filters)](#before-actions-controller-filters)
10. [Soft Delete](#soft-delete)
11. [Model Utilities](#model-utilities)
12. [Transactions](#transactions)
13. [Serialization](#serialization)
14. [Migrations](#migrations)

---

## Generating a Model

Use `forge generate model` to create a model. Pass the model name (PascalCase singular) followed by field definitions as `name:type` pairs.

```bash
forge generate model Post title:string body:text user:references
```

**Supported field types:**

| Type | SQL column |
|---|---|
| `string` | `VARCHAR(255)` |
| `text` | `TEXT` |
| `integer` | `INTEGER` |
| `bigint` | `BIGINT` |
| `boolean` | `BOOLEAN` |
| `float` | `REAL` |
| `decimal` | `NUMERIC` |
| `date` | `DATE` |
| `datetime` | `TIMESTAMP` |
| `references` | `BIGINT` foreign key column (e.g. `user_id`) |

The generator creates two files:

```
app/models/post.jda         — validations + custom scopes (you write this)
db/migrate/001_create_posts.sql  — migration (numbered automatically)
```

`_build/models.jda` is a third file generated automatically at build time from the migration — you never edit it.

### Generated migration

```sql
-- db/migrate/001_create_posts.sql
CREATE TABLE IF NOT EXISTS posts (
  id         BIGSERIAL PRIMARY KEY,
  title      VARCHAR(255),
  body       TEXT,
  user_id    BIGINT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMP
);
```

`deleted_at` is always included to support soft deletes. `id`, `created_at`, `updated_at`, and `deleted_at` are added automatically — do not declare them explicitly.

### Your model file

The generator creates a minimal file with declarative validations and a stub for custom scopes:

```jda
// app/models/post.jda

fn post_validations_init() {
    forge_model("posts")
    forge_field       ("title, body, user_id", FORGE_V_PRESENCE)
    forge_field_length("title",                2, 255)
}
```

Call `post_validations_init()` once in `main.jda` before `routes(app)`. Validations then fire automatically before every insert and update — no explicit call needed in controllers.

Everything else (`post_q`, `post_all`, `post_find`, `post_create`, `post_update`, `post_delete`, …) is generated automatically into `_build/models.jda` by reading the migration. Add custom scopes and helper functions below the validations.

### Auto-generated CRUD (`_build/models.jda`)

`forge build` (and `forge server`) runs `forge compile-models` which reads every `CREATE TABLE` in `db/migrate/` and emits one block per table:

```jda
// === posts ===
fn post_q()                              -> &ForgeQuery  { ret forge_q("posts") }
fn post_all()                            -> &ForgeResult { ret forge_q("posts").order_desc("created_at").exec() }
fn post_find(id: []i8)                   -> &ForgeResult { ret forge_find("posts", id) }
fn post_find_by(col: []i8, val: []i8)   -> &ForgeResult { ret forge_find_by("posts", col, val) }
fn post_where(col: []i8, val: []i8)     -> &ForgeQuery  { ret forge_q("posts").where_eq(col, val) }
fn post_count()                          -> i64          { ret forge_q("posts").count() }
fn post_exists(id: []i8)                -> bool         { ret forge_q("posts").where_eq("id", id).exists() }
fn post_delete(id: []i8)                -> bool         { ret forge_soft_delete("posts", id) }
fn post_destroy(id: []i8)               -> bool         { ret forge_hard_delete("posts", id) }
fn post_touch(id: []i8)                 -> bool         { ret forge_touch("posts", id) }
fn post_update_column(id: []i8, col: []i8, val: []i8) -> bool { ret forge_update_column("posts", id, col, val) }
fn post_find_or_create_by(col: []i8, val: []i8) -> &ForgeResult { ret forge_find_or_create_by("posts", col, val) }
fn post_create(title: []i8, body: []i8, user_id: []i8) -> bool {
    ret forge_attrs_new()
        .set("title",   title)
        .set("body",    body)
        .set("user_id", user_id)
        .insert("posts")
}
fn post_update(id: []i8, title: []i8, body: []i8, user_id: []i8) -> bool {
    ret forge_attrs_new()
        .set("title",   title)
        .set("body",    body)
        .set("user_id", user_id)
        .update("posts", id)
}
fn post_create_from(attrs: &ForgeAttrs) -> bool { ret forge_attrs_insert(attrs, "posts") }
fn post_update_from(id: []i8, attrs: &ForgeAttrs) -> bool { ret forge_attrs_update(attrs, "posts", id) }
```

Column order in `post_create` / `post_update` matches the migration. `BOOLEAN` columns with defaults (e.g. `published`) are excluded from the generated params since the database default handles them — toggle them with `post_update_column` or `.update_all`.

---

## Generated Query Interface

The functions auto-generated per model. These cover the most common operations and serve as the starting point for all queries.

### post_q

Returns a bare `&ForgeQuery` for the `posts` table. Use this when you need the full query builder.

```jda
let q = post_q()
let res = q.where_eq("status", "published").order_desc("created_at").page(1, 20).exec()
```

### post_all

Returns all non-deleted rows ordered by `created_at DESC`.

```jda
let res = post_all()
```

### post_find

Looks up a single row by primary key. Returns a `&ForgeResult` with zero or one row.

```jda
let res = post_find("42")
```

### post_find_by

Looks up a single row by an arbitrary column.

```jda
let res = post_find_by("slug", "hello-world")
```

### post_where

Returns a `&ForgeQuery` pre-filtered by a single column equality condition. Use the returned query to chain additional conditions.

```jda
let res = post_where("user_id", uid).order_asc("title").exec()
```

### post_count

Returns the total row count as `i64`.

```jda
let n = post_count()
```

### post_exists

Returns `true` if a row with the given id exists (and has not been soft-deleted).

```jda
if post_exists("99") {
    // ...
}
```

### post_delete

Soft-deletes a row by setting `deleted_at`. Returns `true` on success.

```jda
let ok = post_delete("42")
```

### post_destroy

Hard-deletes a row with `DELETE FROM`, firing `BEFORE_DELETE` / `AFTER_DELETE` / `AFTER_COMMIT` callbacks. Returns `true` on success.

```jda
let ok = post_destroy("42")
```

### post_touch

Updates only `updated_at = NOW()`, bypassing validations and callbacks.

```jda
post_touch("42")
```

### post_update_column

Updates a single column directly, bypassing validations and callbacks.

```jda
post_update_column("42", "slug", "hello-world")
```

### post_find_or_create_by

Returns the first row matching `col = val`, or inserts a minimal record if none exists.

```jda
let res = post_find_or_create_by("slug", "hello-world")
```

### post_create_from / post_update_from

Insert or update from a `&ForgeAttrs` built by `ctx_permit`. Declarative validations fire automatically.

```jda
if post_create_from(ctx_permit(ctx, "title, body, author")) {
    ctx_redirect(ctx, posts_path)
    ret
}
ctx_save_errors(ctx)
ctx_redirect(ctx, new_post_path)
```

### Extending the generated interface

Add custom scopes, helpers, and domain logic to `app/models/post.jda`. These are plain Jda functions and can use any query builder method.

```jda
// Custom scope: published posts for a given user
fn post_published_by_user(uid: []i8) -> &ForgeResult {
    ret post_q()
        .where_eq("user_id", uid)
        .where_not_null("published_at")
        .where_eq("status", "active")
        .order_desc("published_at")
        .exec()
}

// Count drafts
fn post_draft_count(uid: []i8) -> i64 {
    ret post_q().where_eq("user_id", uid).where_null("published_at").count()
}
```

---

## Query Builder Reference

All query builder methods return `&ForgeQuery` unless noted otherwise, making them chainable. Call `.exec()` or `.all()` at the end to run the query and get a `&ForgeResult`.

### Constructor

```jda
let q = forge_q("posts")
```

Creates a new query targeting the given table. All subsequent methods operate on this query. `forge_q` automatically appends `WHERE deleted_at IS NULL` unless you are using `forge_purge` or have explicitly opted out.

---

### Column Selection

#### .select(cols)

Restrict which columns are returned. Pass a comma-separated string.

```jda
let res = forge_q("posts").select("id, title, published_at").exec()
```

#### .distinct()

Add `DISTINCT` to the SELECT.

```jda
let res = forge_q("posts").select("user_id").distinct().exec()
```

---

### WHERE Conditions

All WHERE methods are safe against SQL injection unless explicitly noted as unsafe.

#### .where_eq(col, val)

Adds `col = 'val'`.

```jda
forge_q("posts").where_eq("status", "published")
```

#### .where(col, op, val)

Adds `col op 'val'`. Use for operators not covered by the named helpers (`=`, `!=`, `<`, `>`, `<=`, `>=`).

```jda
forge_q("orders").where("total", ">", "100")
```

#### .where_not(col, val)

Adds `col != 'val'`.

```jda
forge_q("posts").where_not("status", "draft")
```

#### .where_null(col)

Adds `col IS NULL`.

```jda
forge_q("posts").where_null("published_at")
```

#### .where_not_null(col)

Adds `col IS NOT NULL`.

```jda
forge_q("posts").where_not_null("published_at")
```

#### .where_like(col, pat) / .where_ilike(col, pat)

Pattern matching. `where_ilike` is case-insensitive. Use `%` as a wildcard.

```jda
forge_q("posts").where_ilike("title", "%rails%")
```

#### .where_between(col, lo, hi)

Adds `col BETWEEN 'lo' AND 'hi'`.

```jda
forge_q("events").where_between("starts_at", "2024-01-01", "2024-12-31")
```

#### .where_gt / .where_gte / .where_lt / .where_lte

```jda
forge_q("products").where_gte("price", "10").where_lte("price", "500")
```

#### .where_in(col, list) / .where_not_in(col, list)

Pass a comma-separated string of values.

```jda
forge_q("posts").where_in("status", "draft,published,archived")
forge_q("users").where_not_in("role", "banned,suspended")
```

#### .where_raw(expr)

Inserts a raw SQL fragment directly into the WHERE clause. **Not safe with user-supplied input.** Use only with trusted, hard-coded expressions.

```jda
forge_q("posts").where_raw("published_at < NOW() - INTERVAL '7 days'")
```

#### .where_bind(template, args) — parameterized conditions

Rails-style `?` placeholder substitution. Each `?` is replaced with the next pipe-separated value, SQL-escaped and single-quoted. Values must not contain `|`.

```jda
// Two conditions in one call
forge_q("users").where_bind("role = ? and status = ?", "admin|active")

// With comparison operators
forge_q("orders").where_bind("total > ? and total <= ?", "100|500")

// Mixing with other where methods
forge_q("posts")
    .where_bind("title ILIKE ? and author = ?", "%forge%|alice")
    .where_not_null("published_at")
    .order_desc("created_at")
    .exec()
```

For simple equality, `where_eq` is clearer. Use `where_bind` when you need operators or multiple conditions in one expression.

#### Chaining multiple conditions

Chaining multiple WHERE methods produces `AND` conditions.

```jda
let res = forge_q("posts")
    .where_eq("status", "published")
    .where_eq("role", "editor")
    .where_not_null("published_at")
    .exec()
// SQL: WHERE status = 'published' AND role = 'editor' AND published_at IS NOT NULL
```

---

### OR Conditions

#### .or()

The `.or()` call makes the **next** condition use `OR` instead of `AND`.

```jda
let res = forge_q("posts")
    .where_eq("status", "published")
    .or()
    .where_eq("status", "featured")
    .exec()
// SQL: WHERE status = 'published' OR status = 'featured'
```

`.or()` only affects the single condition immediately following it. Subsequent conditions revert to `AND`.

```jda
forge_q("posts")
    .where_eq("author_id", uid)
    .or()
    .where_eq("co_author_id", uid)
    .where_not_null("published_at")   // AND again
    .exec()
// SQL: WHERE author_id = '...' OR co_author_id = '...' AND published_at IS NOT NULL
```

---

### JOINs

#### .join(table, cond)

Inner join using an explicit ON condition.

```jda
forge_q("posts")
    .join("users", "users.id = posts.user_id")
    .select("posts.*, users.name AS author_name")
    .exec()
```

#### .left_join(table, cond)

Left outer join.

```jda
forge_q("posts").left_join("comments", "comments.post_id = posts.id")
```

#### .inner_join(table, cond)

Explicit inner join (same as `.join`).

#### .join_raw(expr)

Raw JOIN fragment. Not safe with user input.

```jda
forge_q("posts").join_raw("JOIN tags ON tags.id = ANY(posts.tag_ids)")
```

---

### Grouping and HAVING

#### .group(cols)

Adds a `GROUP BY` clause.

```jda
forge_q("posts")
    .select("user_id, COUNT(*) AS post_count")
    .group("user_id")
    .exec()
```

#### .having(expr)

Adds a `HAVING` clause. Use after `.group()`.

```jda
forge_q("posts")
    .select("user_id, COUNT(*) AS post_count")
    .group("user_id")
    .having("COUNT(*) > 5")
    .exec()
```

---

### Ordering

#### .order(col, dir)

Order by column and direction (`"ASC"` or `"DESC"`).

```jda
forge_q("posts").order("title", "ASC")
```

#### .order_asc(col) / .order_desc(col)

Convenience wrappers.

```jda
forge_q("posts").order_desc("created_at").order_asc("title")
```

Multiple `.order_*` calls append to the ORDER BY clause in the sequence called.

---

### Pagination and Limits

#### .limit(n)

Limits result rows. Pass an `i64`.

```jda
forge_q("posts").limit(10)
```

#### .offset(n)

Skips the first `n` rows.

```jda
forge_q("posts").limit(10).offset(20)
```

#### .page(page, per)

Convenience pagination. `page` is 1-indexed; `per` is rows per page.

```jda
let res = forge_q("posts").order_desc("created_at").page(3, 25).exec()
// SQL: LIMIT 25 OFFSET 50
```

---

### Execution

#### .exec() / .all()

Both compile and run the query, returning `&ForgeResult`. They are identical; `all()` is provided for readability.

```jda
let res = forge_q("posts").where_eq("status", "published").exec()
let res = forge_q("posts").where_eq("status", "published").all()
```

#### .first()

Returns a `&ForgeResult` with at most one row — the first by the current ORDER, or by default insertion order.

```jda
let res = forge_q("posts").order_asc("created_at").first()
```

#### .last()

Returns a `&ForgeResult` with the last row.

```jda
let res = forge_q("posts").order_asc("created_at").last()
```

#### .pluck(col)

Returns a `&ForgeResult` containing only the values of a single column.

```jda
let ids = forge_q("posts").where_eq("user_id", uid).pluck("id")
```

---

### Aggregates

These terminate the chain and return a value directly.

#### .count() -> i64

```jda
let n = forge_q("posts").where_eq("status", "published").count()
```

#### .exists() -> bool

```jda
if forge_q("users").where_eq("email", email).exists() {
    // email already taken
}
```

#### .sum(col) / .avg(col) / .max(col) / .min(col) -> []i8

Aggregate functions return their result as a string slice (`[]i8`). Parse as needed.

```jda
let total = forge_q("orders").where_eq("user_id", uid).sum("total")
let avg   = forge_q("products").where_eq("category", "books").avg("price")
let max   = forge_q("bids").where_eq("auction_id", aid).max("amount")
```

---

### DML: Bulk Update and Delete

#### .update_all(set_clause) -> bool

Applies a raw SET clause to all rows matching the current WHERE conditions. Returns `true` on success.

```jda
let ok = forge_q("posts")
    .where_eq("user_id", uid)
    .update_all("status = 'archived', updated_at = NOW()")
```

**Caution:** `update_all` does not trigger callbacks. Do not interpolate user input into `set_clause`.

#### .delete_all() -> bool

Hard-deletes all rows matching the current WHERE conditions. Returns `true` on success.

```jda
let ok = forge_q("sessions").where_eq("user_id", uid).delete_all()
```

**Caution:** `delete_all` bypasses soft delete and callbacks. Prefer `post_delete` for soft deletes.

---

## Named Scopes

Named scopes are reusable query fragments registered against a table. They are applied via `.scope(name)` in a query chain.

### Defining a scope

A scope is a plain Jda function that accepts a `&ForgeQuery` and applies conditions to it in-place using the global `forge_q_*` functions (the UFCS-free form).

```jda
fn scope_published(q: &ForgeQuery) {
    forge_q_where_not_null(q, "published_at")
    forge_q_where_eq(q, "status", "active")
}

fn scope_recent(q: &ForgeQuery) {
    forge_q_where_raw(q, "created_at > NOW() - INTERVAL '30 days'")
    forge_q_order_desc(q, "created_at")
}
```

### Registering a scope

```jda
forge_scope_register("posts", "published", fn_addr(scope_published))
forge_scope_register("posts", "recent",    fn_addr(scope_recent))
```

Call `forge_scope_register` once at application startup (e.g. in your initializer or `main`).

### Using a scope

```jda
let res = forge_q("posts").scope("published").order_desc("created_at").page(1, 25).exec()
```

Scopes compose with each other and with manual conditions:

```jda
let res = forge_q("posts")
    .scope("published")
    .scope("recent")
    .where_eq("user_id", uid)
    .exec()
```

---

## Batch Processing

`forge_find_in_batches` iterates over large result sets without loading all rows into memory at once. It calls a callback function with each batch as a `&ForgeResult`.

```jda
fn process_batch(res: &ForgeResult) {
    loop i in 0..res.count {
        let email = forge_result_col(res, i, "email")
        // process row...
    }
}

forge_find_in_batches("users", 500, fn_addr(process_batch))
```

The second argument is the batch size. `forge_find_in_batches` issues multiple queries internally, ordering by `id ASC` and using keyset pagination.

---

## Validations

Forge supports two validation styles: **declarative** (Rails-style, fires automatically on save) and **manual** (explicit calls you control). Prefer declarative for standard rules; fall back to manual for complex cross-field logic.

### Declarative validations

Register rules once at startup. They fire automatically inside every `post_create` and `post_update` call — you never call them in the controller.

Call `forge_model(table)` once at the top of your init function to set the model context, then use the short `forge_field*` helpers — no need to repeat the table name on every line:

```jda
// app/models/post.jda
fn post_validations_init() {
    forge_model("posts")
    forge_field       ("title, body, author", FORGE_V_PRESENCE)
    forge_field_length("title",               2, 255)
    forge_field_min   ("body",                10)
    forge_field       ("email",               FORGE_V_EMAIL)
    forge_field_param ("status",              FORGE_V_INCLUSION, "draft,published,archived")
}
```

Call the init function once at startup — typically in `main.jda` before `routes(app)`:

```jda
post_validations_init()
routes(app)
```

In the controller, just call the CRUD function. If validation fails it returns `false` and `forge_last_errors()` holds the errors:

```jda
fn posts_create(ctx: i64) {
    let ok = post_create(ctx_form(ctx, "title"), ctx_form(ctx, "body"), ctx_form(ctx, "author"))
    if not ok {
        let errs = forge_last_errors()
        if forge_errors_any(errs) {
            ctx_unprocessable(ctx, forge_errors_json(errs))
        } else {
            ctx_unprocessable(ctx, "Could not save post.")
        }
        ret
    }
    ctx_redirect(ctx, posts_path)
}
```

#### Rails → Forge validation reference

| Rails | Forge (declarative) | Notes |
|---|---|---|
| `validates :f, presence: true` | `forge_field("f", FORGE_V_PRESENCE)` | |
| `validates :f, absence: true` | `forge_field("f", FORGE_V_ABSENCE)` | |
| `validates :f, :g, presence: true` | `forge_field("f, g", FORGE_V_PRESENCE)` | comma-separated |
| `validates :f, length: { minimum: 2 }` | `forge_field_min("f", 2)` | |
| `validates :f, length: { maximum: 255 }` | `forge_field_param("f", FORGE_V_MAX_LEN, "255")` | |
| `validates :f, length: { minimum: 2, maximum: 255 }` | `forge_field_length("f", 2, 255)` | |
| `validates :f, length: { is: 10 }` | `forge_field_exact("f", 10)` | |
| `validates :f, numericality: true` | `forge_field("f", FORGE_V_NUMERICALITY)` | digits only |
| `validates :f, numericality: { greater_than: 0 }` | `forge_field_gt("f", 0)` | |
| `validates :f, numericality: { greater_than_or_equal_to: 18 }` | `forge_field_gte("f", 18)` | |
| `validates :f, numericality: { less_than: 100 }` | `forge_field_lt("f", 100)` | |
| `validates :f, numericality: { less_than_or_equal_to: 65 }` | `forge_field_lte("f", 65)` | |
| `validates :f, numericality: { equal_to: 42 }` | `forge_field_equal_to("f", 42)` | |
| `validates :f, format: { with: URI::MailTo::EMAIL_REGEXP }` | `forge_field("f", FORGE_V_EMAIL)` | |
| `validates :f, format: { with: URI }` | `forge_field("f", FORGE_V_URL)` | http/https + dot |
| `validates :f, inclusion: { in: %w[a b c] }` | `forge_field_param("f", FORGE_V_INCLUSION, "a,b,c")` | |
| `validates :f, exclusion: { in: %w[admin root] }` | `forge_field_param("f", FORGE_V_EXCLUSION, "admin,root")` | |
| `validates :f, acceptance: true` | `forge_field_acceptance("f")` | "1" or "true" |
| `validates :f, confirmation: true` | `forge_field_confirm("f", "f_confirmation")` | ¹ |
| `validates :f, uniqueness: true` | `forge_validate_uniqueness(e, table, f, val, id)` | manual only ² |

¹ The confirmation field must be included in `forge_attrs_set` calls — it is not a DB column but must be passed as an attribute.

² Uniqueness requires a DB query and knowledge of the current record's id (to exclude it on update). Use it directly in a `FORGE_CB_BEFORE_SAVE` callback or call it explicitly before saving:

```jda
fn user_create_handler(ctx: i64) {
    let email = ctx_form(ctx, "email")
    let e = forge_errors_new()
    forge_validate_uniqueness(e, "users", "email", email, "")
    if forge_errors_any(e) {
        ctx_unprocessable(ctx, forge_errors_json(e))
        ret
    }
    user_create(email, ctx_form(ctx, "password"))
    ctx_redirect(ctx, login_path)
}
```

#### Context helpers (use after `forge_model`)

```jda
forge_model          (table)
forge_field          ("f, g", rule)          // one or more fields, same rule
forge_field_length   ("f", min, max)
forge_field_min      ("f", min)
forge_field_exact    ("f", n)
forge_field_gt       ("f", n)
forge_field_gte      ("f", n)
forge_field_lt       ("f", n)
forge_field_lte      ("f", n)
forge_field_equal_to ("f", n)
forge_field_url      ("f")
forge_field_absence  ("f")
forge_field_acceptance("f")
forge_field_confirm  ("password", "password_confirmation")
forge_field_param    ("f", rule, param)      // any rule with a string param
```

#### Low-level helpers (pass table explicitly)

```jda
forge_validates        (table, field, rule)
forge_validates_fields (table, "f, g", rule)
forge_validates_param  (table, field, rule, param)
forge_validates_length (table, field, min, max)
forge_validates_min_len(table, field, min)
```

### Lifecycle order

When `forge_attrs_insert` or `forge_attrs_update` is called, the order is:

1. Declarative validations — abort and set `forge_last_errors()` if any fail
2. `FORGE_CB_BEFORE_SAVE` callbacks
3. `FORGE_CB_BEFORE_CREATE` / `FORGE_CB_BEFORE_UPDATE` callbacks
4. SQL INSERT / UPDATE
5. On success: `FORGE_CB_AFTER_CREATE` / `FORGE_CB_AFTER_UPDATE` → `FORGE_CB_AFTER_SAVE` → `FORGE_CB_AFTER_COMMIT`
6. On DB failure: `FORGE_CB_AFTER_ROLLBACK`

For `forge_soft_delete`: `FORGE_CB_BEFORE_DELETE` → SQL → `FORGE_CB_AFTER_DELETE` + `FORGE_CB_AFTER_COMMIT` on success, or `FORGE_CB_AFTER_ROLLBACK` on failure.

---

### Manual validators

For complex or cross-field validation, call the low-level helpers directly and return a `&ForgeErrors` from your own function:

```jda
let e = forge_errors_new()
```

#### Available validators

#### forge_validate_presence

Fails if the value is empty or all whitespace.

```jda
forge_validate_presence(e, "title", title)
```

#### forge_validate_length

Fails if the string length is outside `[min, max]`.

```jda
forge_validate_length(e, "title", title, 2, 255)
```

#### forge_validate_min_length

Fails if the string is shorter than `min`.

```jda
forge_validate_min_length(e, "body", body, 10)
```

#### forge_validate_format_email

Fails if the value does not look like a valid email address.

```jda
forge_validate_format_email(e, "email", email)
```

#### forge_validate_numericality

Fails if the value cannot be parsed as a number.

```jda
forge_validate_numericality(e, "age", age)
```

#### forge_validate_confirmation

Fails if `value` and `confirm` differ. Used for password confirmation fields.

```jda
forge_validate_confirmation(e, "password", password, confirm)
```

#### forge_validate_inclusion

Fails if the value is not in the comma-separated `allowed` string.

```jda
forge_validate_inclusion(e, "role", role, "admin,user,guest")
```

### Checking and rendering errors (manual validation)

When using manual validation, run your validate function explicitly and check before saving:

```jda
fn posts_create(ctx: i64) {
    let title = ctx_param(ctx, "title")
    let body  = ctx_param(ctx, "body")
    let errs  = user_validate_complex(title, body)
    if forge_errors_any(errs) {
        ctx_unprocessable(ctx, forge_errors_json(errs))
        ret
    }
    post_create(title, body)
    ctx_redirect(ctx, posts_path)
}
```

`forge_errors_json` returns a JSON object mapping field names to error messages:

```json
{"errors":{"title":"can't be blank","body":"is too short"}}
```

**Error helper functions:**

| Function | Returns | Description |
|---|---|---|
| `forge_errors_any(e)` | `bool` | True if there are any errors. |
| `forge_errors_count(e)` | `i64` | Number of errors. |
| `forge_errors_json(e)` | `[]i8` | `{"errors":{"field":"msg",...}}` — keyed by field. |
| `forge_errors_full_messages(e)` | `[]i8` | `"Title can't be blank, Body is too short"` — human string. |
| `forge_errors_full_messages_json(e)` | `[]i8` | `["Title can't be blank","Body is too short"]` — JSON array. |

### Using multiple validators on the same field

Call validators in sequence. All validators run; errors accumulate.

```jda
fn user_validate(email: []i8, password: []i8, confirm: []i8, role: []i8, age: []i8) -> &ForgeErrors {
    let e = forge_errors_new()
    forge_validate_presence(e, "email", email)
    forge_validate_format_email(e, "email", email)
    forge_validate_presence(e, "password", password)
    forge_validate_min_length(e, "password", password, 8)
    forge_validate_confirmation(e, "password", password, confirm)
    forge_validate_inclusion(e, "role", role, "admin,user,guest")
    forge_validate_numericality(e, "age", age)
    ret e
}
```

---

## Associations

Forge provides three association helpers. They return a `&ForgeResult` (or a single row result for `has_one` / `belongs_to`).

### belongs_to

Fetches the parent record by a foreign key value.

```jda
// Given a post row with a user_id field:
let user = forge_belongs_to("users", post.user_id)
```

Equivalent to `forge_find("users", post.user_id)`.

### has_many

Fetches all child rows for a given foreign key.

```jda
let posts = forge_has_many("posts", "user_id", uid)
```

Returns all posts where `user_id = uid`, ordered by `created_at DESC`. Soft-deleted rows are excluded.

### has_one

Fetches a single child row for a given foreign key. Returns the first match.

```jda
let profile = forge_has_one("profiles", "user_id", uid)
```

### Combining with the query builder

For filtered associations, use `forge_q` directly:

```jda
// Published posts for a user, paginated
let posts = forge_q("posts")
    .where_eq("user_id", uid)
    .where_not_null("published_at")
    .order_desc("published_at")
    .page(page, 20)
    .exec()
```

---

## Callbacks

Callbacks let you hook into the record lifecycle. A callback is a plain Jda function that receives a pointer to the row data and returns `bool`. Returning `false` from a before-callback aborts the operation.

Declarative validations always run before any before-callback. See [Lifecycle order](#lifecycle-order) in the Validations section.

### Registering a callback

```jda
forge_callback_add("users", FORGE_CB_BEFORE_SAVE,   fn_addr(hash_password_before_save))
forge_callback_add("users", FORGE_CB_AFTER_CREATE,  fn_addr(send_welcome_email))
forge_callback_add("users", FORGE_CB_BEFORE_DELETE, fn_addr(cancel_subscriptions))
```

Register callbacks once at startup.

### Callback function signature

```jda
fn hash_password_before_save(row_ptr: i64) -> bool {
    // row_ptr is a pointer to the row struct in memory
    // Return false to abort the save
    ret true
}
```

### Available callback constants

| Constant | Fires |
|---|---|
| `FORGE_CB_BEFORE_SAVE` | Before any INSERT or UPDATE |
| `FORGE_CB_AFTER_SAVE` | After any INSERT or UPDATE |
| `FORGE_CB_BEFORE_CREATE` | Before INSERT only |
| `FORGE_CB_AFTER_CREATE` | After INSERT only |
| `FORGE_CB_BEFORE_UPDATE` | Before UPDATE only |
| `FORGE_CB_AFTER_UPDATE` | After UPDATE only |
| `FORGE_CB_BEFORE_DELETE` | Before soft or hard delete |
| `FORGE_CB_AFTER_DELETE` | After soft or hard delete |
| `FORGE_CB_AFTER_COMMIT` | After any successful INSERT, UPDATE, or DELETE |
| `FORGE_CB_AFTER_ROLLBACK` | After a failed INSERT, UPDATE, or DELETE (DB error only — not validation failure) |

### Notes

- Multiple callbacks can be registered for the same table and event; they fire in registration order.
- `update_all` and `delete_all` do not trigger callbacks.
- A before-callback returning `false` prevents the operation and stops the callback chain.

---

## Before Actions (Controller Filters)

Like Rails `before_action`, Forge lets you register filter functions that run before selected controller actions. The filter loads shared data (e.g. the current post) into the request context via `ctx_set`; actions read it back with `ctx_get`.

### Pattern

```jda
// 1. The filter — loads post, stores on context, sends 404 on miss
fn posts_set_post(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    if post.count == 0 { ctx_not_found(ctx)  ret }
    ctx_set(ctx, "post", post as i64)
}

// 2. Actions read from context instead of doing their own lookup
fn posts_show(ctx: i64) {
    let post: &ForgeResult = ctx_get(ctx, "post") as &ForgeResult
    ctx_render(ctx, view_posts_show(ctx, post))
}

fn posts_edit(ctx: i64) {
    let post: &ForgeResult = ctx_get(ctx, "post") as &ForgeResult
    ctx_render(ctx, view_posts_edit(ctx, post))
}

// 3. Register — call once at startup, before forge_controllers_init()
fn posts_before_actions() {
    let ctrl = forge_ctrl_new()
    forge_ctrl_before(ctrl, fn_addr(posts_set_post), "show, edit, update, delete")
    forge_ctrl_register("posts", ctrl)
}
```

In `main.jda`:

```jda
fn main() {
    load_env()
    let app = app_new_config(app_config())
    // middleware ...
    post_validations_init()
    posts_before_actions()          // register before actions
    forge_controllers_init()        // register action handlers
    routes(app)
    forge_migration_run("db/migrate")
    app_listen(app, str_to_i32(forge_env_get("APP_PORT")))
}
```

### How it works

`forge build` generates a dispatch shim for every action in `_build/controllers.jda`:

```jda
fn forge__dispatch_posts_show(ctx: i64) {
    forge_ctrl_run("posts", "show", fn_addr(posts_show), ctx)
}
```

`forge_ctrl_run` looks up the registered controller for `"posts"`. If none is registered it calls the action directly (zero overhead). If one is registered, it runs through `forge_ctrl_dispatch` which fires matching before filters, then the action, then any after filters.

If a filter sends a response (e.g. `ctx_not_found`), the action and remaining filters are skipped.

### API

| Function | Description |
|---|---|
| `forge_ctrl_new() -> &ForgeController` | Create a new controller filter set. |
| `forge_ctrl_before(ctrl, fn_ptr, only)` | Register a before filter. `only` is a comma-separated action list or `""` for all actions. |
| `forge_ctrl_after(ctrl, fn_ptr, only)` | Register an after filter. |
| `forge_ctrl_register(name, ctrl)` | Bind the controller to a resource name (e.g. `"posts"`). |
| `ctx_set(ctx, key, val)` | Store an `i64` value on the request context. |
| `ctx_get(ctx, key) -> i64` | Retrieve a stored value; cast to the original type with `as`. |

### only — matching rules

- `""` — fires for every action
- `"show"` — exact match
- `"show, edit, update, delete"` — comma-separated, spaces optional

---

## Soft Delete

All generated tables include a `deleted_at TIMESTAMP` column. The soft delete helpers set or clear this column instead of removing rows.

### Soft-deleting a row

```jda
let ok = forge_soft_delete("posts", id)
```

Sets `deleted_at = NOW()`. The row is excluded from all queries built with `forge_q` automatically.

The generated `post_delete` wrapper calls `forge_soft_delete` internally.

### Restoring a soft-deleted row

```jda
let ok = forge_restore("posts", id)
```

Sets `deleted_at = NULL`, making the row visible again.

### Hard-deleting a row (with callbacks)

```jda
let ok = forge_hard_delete("posts", id)     // fires BEFORE/AFTER_DELETE + AFTER_COMMIT
```

Generated wrapper: `post_destroy(id)` — calls `forge_hard_delete` and fires the full callback lifecycle.

### Hard-deleting a row (no callbacks)

```jda
let ok = forge_purge("posts", id)           // raw DELETE, skips all callbacks
```

Permanently removes the row without firing any callbacks. Like Rails `Model.delete` vs `Model.destroy`.

### Querying deleted rows

`forge_q` always appends `WHERE deleted_at IS NULL`. To include soft-deleted rows, use `.where_raw` to override:

```jda
// Include deleted rows
let res = forge_q("posts").where_raw("1=1").exec()

// Only deleted rows
let res = forge_q("posts").where_not_null("deleted_at").where_raw("deleted_at IS NOT NULL").exec()
```

---

## Model Utilities

### forge_touch

Updates only `updated_at` without running validations or callbacks.

```jda
forge_touch("posts", id)
post_touch(id)              // generated wrapper
```

### forge_update_column

Updates a single column directly, bypassing validations and callbacks.

```jda
forge_update_column("posts", id, "slug", "hello-world")
post_update_column(id, "slug", "hello-world")    // generated wrapper
```

### forge_find_or_create_by

Returns the first matching row, or creates a minimal record if none exists.

```jda
let res = forge_find_or_create_by("users", "email", "alice@example.com")
let res = user_find_or_create_by("email", "alice@example.com")    // generated wrapper
```

### forge_attrs_upsert

`INSERT ... ON CONFLICT (col) DO UPDATE SET ...` — insert or update on a unique column.

```jda
let ok = forge_attrs_new()
    .set("email", email)
    .set("name", name)
    .upsert("users", "email")         // UFCS: forge_attrs_upsert(a, "users", "email")
```

---

## Transactions

Use transactions when multiple writes must succeed or fail together.

### Block-style (recommended)

Pass a function pointer whose return value determines commit vs rollback:

```jda
fn transfer_fn(ignored: i64) -> bool {
    let ok1 = forge_db_exec("UPDATE accounts SET balance = balance - 100 WHERE id = '42'")
    if not ok1 { ret false }
    let ok2 = forge_db_exec("UPDATE accounts SET balance = balance + 100 WHERE id = '99'")
    ret ok2
}

forge_transaction(transfer_fn as i64)
```

Returns `true` if committed, `false` if rolled back.

### Manual

```jda
if not forge_begin() { ret }

let ok = forge_db_exec("UPDATE accounts SET balance = balance - 100 WHERE id = '42'")
if not ok { forge_rollback()  ret }

let ok2 = forge_db_exec("UPDATE accounts SET balance = balance + 100 WHERE id = '99'")
if not ok2 { forge_rollback()  ret }

forge_commit()
```

### API

| Function | Returns | Description |
|---|---|---|
| `forge_begin()` | `bool` | Issues `BEGIN`. |
| `forge_commit()` | `bool` | Issues `COMMIT`. |
| `forge_rollback()` | `bool` | Issues `ROLLBACK`. |
| `forge_transaction(fn_ptr)` | `bool` | Runs fn in a BEGIN/COMMIT block; rolls back if fn returns false. |

---

## Serialization

Forge can serialize query results to JSON strings for use in API responses.

### Serialize a full result set

```jda
let res  = post_all()
let json = forge_result_to_json(res)
// json: '[{"id":"1","title":"Hello","body":"World",...},...]'
```

### Serialize a single row

```jda
let res = post_find("42")
let obj = forge_row_to_json(res, 0)
// obj: '{"id":"42","title":"Hello","body":"World",...}'
```

The second argument to `forge_row_to_json` is the row index (zero-based). All column values are returned as strings in the JSON output.

### JSON response helpers

| Function | Status | Description |
|---|---|---|
| `ctx_json_ok(ctx, json)` | 200 | Send JSON with 200 OK. |
| `ctx_json_created(ctx, json)` | 201 | Send JSON with 201 Created. |
| `ctx_json_errors(ctx)` | 422 | Send `forge_last_errors()` body with 422. |

### Format-aware controllers (respond_to)

Branch on Accept header or `?format=` param:

```jda
fn posts_show_html(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    ctx_render(ctx, view_posts_show(ctx, post))
}

fn posts_show_json(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    ctx_json_ok(ctx, forge_row_to_json(post, 0))
}

fn posts_show(ctx: i64) {
    ctx_respond_to(ctx, posts_show_html as i64, posts_show_json as i64)
}
```

### Typical API controller

```jda
fn api_post_show(ctx: i64) {
    let res = post_find(ctx_param(ctx, "id"))
    if res.count == 0 { ctx_not_found(ctx)  ret }
    ctx_json_ok(ctx, forge_row_to_json(res, 0))
}

fn api_posts_index(ctx: i64) {
    ctx_json_ok(ctx, forge_result_to_json(post_all()))
}

fn api_posts_create(ctx: i64) {
    if post_create_from(ctx_permit(ctx, "title, body, author")) {
        ctx_json_created(ctx, "{\"ok\":true}")
        ret
    }
    ctx_json_errors(ctx)
}
```

---

## Migrations

Migrations are plain SQL files in `db/migrations/`. They are numbered and run once in order.

### File naming convention

```
db/migrations/
  001_create_posts.sql
  002_create_users.sql
  003_add_slug_to_posts.sql
  004_add_index_users_email.sql
```

- Files must start with a zero-padded three-digit number.
- The name after the number is descriptive and has no effect on execution.
- Files are run in ascending numeric order.
- Each file is tracked in a `forge_schema_migrations` table; a file is never run twice.

### Writing a migration

Any valid SQL is accepted. Multiple statements are separated by semicolons.

```sql
-- db/migrations/003_add_slug_to_posts.sql
ALTER TABLE posts ADD COLUMN slug VARCHAR(255);
CREATE UNIQUE INDEX idx_posts_slug ON posts (slug);
```

### Running migrations

```jda
forge_migration_run("db/migrations")
```

Call this once at application startup, before handling any requests. It reads the directory, compares file numbers against the `forge_schema_migrations` tracking table, and runs any unapplied files in order.

### Generating a migration from the CLI

```bash
forge generate migration add_slug_to_posts
```

Creates the next numbered file in `db/migrations/`:

```
db/migrations/003_add_slug_to_posts.sql
```

The file is created empty; fill it with your SQL.

### Generating a model migration

`forge generate model` also generates the initial migration automatically. You do not need to create it by hand.

```bash
forge generate model Comment body:text post:references user:references
# Creates:
#   models/comment.jda
#   db/migrations/005_create_comments.sql
```

### Schema tracking table

Forge creates `forge_schema_migrations` automatically on first run:

```sql
CREATE TABLE IF NOT EXISTS forge_schema_migrations (
  version VARCHAR(10) PRIMARY KEY,
  run_at  TIMESTAMP NOT NULL DEFAULT NOW()
);
```

Do not modify this table manually.

### Rollbacks

Forge does not automatically generate down migrations. If you need to reverse a migration, write a new numbered migration that undoes the change:

```sql
-- db/migrations/006_remove_slug_from_posts.sql
ALTER TABLE posts DROP COLUMN slug;
```
