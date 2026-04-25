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
15. [Counter Caches](#counter-caches)
16. [Dirty Tracking](#dirty-tracking)
17. [Single Table Inheritance (STI)](#single-table-inheritance-sti)
18. [Enum Helpers](#enum-helpers)
19. [Bulk Operations: find_or_init_by and insert_all](#bulk-operations-find_or_init_by-and-insert_all)

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

fn post_model_init() {
    forge_model("posts")
    forge_field       ("title, body, user_id", FORGE_V_PRESENCE)
    forge_field_length("title",                2, 255)
}
```

Call `post_model_init()` once in `main.jda` before `routes(app)`. Validations then fire automatically before every insert and update — no explicit call needed in controllers.

Everything else (`post_q`, `post_all`, `post_find`, `post_create`, `post_update`, `post_delete`, …) is generated automatically into `_build/models.jda` by reading the migration. Add custom scopes and helper functions below the validations.

### Auto-generated CRUD (`_build/models.jda`)

`forge build` (and `forge server`) runs `forge compile-models` which reads every `CREATE TABLE` in `db/migrate/` and emits one block per table. When the table has a `deleted_at` column, finders are wrapped in `forge_q_where_not_deleted` so they automatically exclude soft-deleted rows:

```jda
// === posts === (table has deleted_at — soft-delete scoped)
fn post_q()                 -> &ForgeQuery  { ret forge_q_where_not_deleted(forge_q("posts")) }
fn post_all()               -> &ForgeResult { ret forge_q_where_not_deleted(forge_q("posts")).order_desc("created_at").exec() }
fn post_find(id: []i8)      -> &ForgeResult { ret forge_q_where_not_deleted(forge_q("posts")).where_eq("id", id).first() }
fn post_find_by(col: []i8, val: []i8)   -> &ForgeResult { ret forge_q_where_not_deleted(forge_q("posts")).where_eq(col, val).first() }
fn post_where(col: []i8, val: []i8)     -> &ForgeQuery  { ret forge_q_where_not_deleted(forge_q("posts")).where_eq(col, val) }
fn post_count()             -> i64  { ret forge_q_where_not_deleted(forge_q("posts")).count() }
fn post_exists(id: []i8)    -> bool { ret forge_q_where_not_deleted(forge_q("posts")).where_eq("id", id).exists() }
fn post_with_deleted()      -> &ForgeQuery { ret forge_q_with_deleted(forge_q("posts")) }
fn post_only_deleted()      -> &ForgeQuery { ret forge_q_only_deleted(forge_q("posts")) }
fn post_delete(id: []i8)    -> bool { ret forge_soft_delete("posts", id) }
fn post_destroy(id: []i8)   -> bool { ret forge_hard_delete("posts", id) }
fn post_touch(id: []i8)     -> bool { ret forge_touch("posts", id) }
fn post_update_column(id: []i8, col: []i8, val: []i8) -> bool { ret forge_update_column("posts", id, col, val) }
fn post_find_or_create_by(col: []i8, val: []i8) -> &ForgeResult { ret forge_find_or_create_by("posts", col, val) }
fn post_reload(id: []i8)    -> &ForgeResult { ret forge_reload("posts", id) }
fn post_toggle(id: []i8, col: []i8) -> bool { ret forge_toggle("posts", id, col) }
fn post_increment(id: []i8, col: []i8, by: i64) -> bool { ret forge_increment("posts", id, col, by) }
fn post_decrement(id: []i8, col: []i8, by: i64) -> bool { ret forge_decrement("posts", id, col, by) }
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

Column order in `post_create` / `post_update` matches the migration. `BOOLEAN` columns with defaults (e.g. `published`) are excluded from the generated params — toggle them with `post_toggle` or `post_update_column`.

### Auto-generated row structs

`compile_models` also emits a typed struct and converter for every table so you can access columns as fields instead of repeated `forge_result_col` calls:

```jda
// Generated for the posts table
struct PostRow {
    id:         []i8
    title:      []i8
    body:       []i8
    author:     []i8
    created_at: []i8
    updated_at: []i8
    deleted_at: []i8
}

fn post_row(result: &ForgeResult, r: i64) -> &PostRow { ... }
```

Use it in views and anywhere you want cleaner field access:

```jda
// controller passes &ForgeResult as before
let post = post_find(id)

// view converts to typed row
let p = post_row(post, 0)
p.title      // instead of forge_result_col(post, 0, "title")
p.id
p.created_at
```

In templates call `post_row(posts, r)` inline to pass a typed object to a partial:

```html
<% loop r in 0..posts.count { %>
<%== tmpl_post_row(post_row(posts, r)) %>
<% } %>
```

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

### post_with_deleted / post_only_deleted

Return a `&ForgeQuery` that includes soft-deleted rows (`with_deleted`) or queries only deleted rows (`only_deleted`). Only generated for tables with a `deleted_at` column.

```jda
let all_including_deleted = post_with_deleted().exec()
let trash = post_only_deleted().order_desc("deleted_at").exec()
```

### post_reload

Re-fetches the record from the database. Bypasses soft-delete scoping so it works on deleted rows too.

```jda
let fresh = post_reload("42")
```

### post_toggle

Flips a boolean column in place: `SET col = NOT col`.

```jda
post_toggle("42", "published")    // flips the published flag
```

### post_increment / post_decrement

Atomically increments or decrements a numeric column by `by`. Bypasses validations and callbacks.

```jda
post_increment("42", "view_count", 1)
post_decrement("42", "stock",      3)
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

Creates a new query targeting the given table. All subsequent methods operate on this query. `forge_q` does **not** add any soft-delete filter by default — use `forge_q_where_not_deleted(q)` to add `WHERE deleted_at IS NULL`, or use the generated per-table helpers (`post_q()`, `post_all()`, etc.) which apply the filter automatically when the table has a `deleted_at` column.

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
forge_q("posts").where_ilike("title", "%jda%")
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

`?` placeholder substitution. Each `?` is replaced with the next pipe-separated value, SQL-escaped and single-quoted. Values must not contain `|`.

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

#### .pick(col)

Returns the value of a single column from the first matching row as `[]i8`. Equivalent to `.select(col).first()` then reading the cell.

```jda
let title = post_q().where_eq("slug", "hello-world").pick("title")
```

---

### Ordering (extended)

#### .reorder(col, dir)

Clears the current `ORDER BY` and replaces it with a new one. Useful when overriding a default order set by a scope.

```jda
let res = post_q().reorder("title", "ASC").exec()
```

#### .reverse_order()

Flips `ASC` to `DESC` or vice-versa in the current order clause. If no order is set, defaults to `id DESC`.

```jda
let oldest_first = post_q().reverse_order().exec()
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

### forge_find_in_batches

Iterates over large result sets in batches without loading all rows into memory. Calls a callback function with each batch as a `&ForgeResult`.

```jda
fn process_batch(res: &ForgeResult) {
    loop i in 0..res.count {
        let email = forge_result_col(res, i, "email")
        // process row...
    }
}

forge_find_in_batches("users", 500, fn_addr(process_batch))
```

The second argument is the batch size. `forge_find_in_batches` issues multiple queries internally, ordering by `id ASC` and using offset pagination.

### forge_q_find_each

Iterates one row at a time using an existing query. The callback receives a single-row `&ForgeResult` cast to `i64`.

```jda
fn process_row(row: i64) {
    let res: &ForgeResult = row as &ForgeResult
    let email = forge_result_col(res, 0, "email")
    // process single row...
}

post_q().where_not_null("email").find_each(fn_addr(process_row))
```

Use `find_each` when you want full query builder control (filters, ordering) or when you need to process rows one at a time rather than in batches.

---

## Validations

Forge supports two validation styles: **declarative** (fires automatically on save) and **manual** (explicit calls you control). Prefer declarative for standard rules; fall back to manual for complex cross-field logic.

### Model init — the full picture

The `*_model_init` function is the single place where the complete shape of a model is declared. Associations, callbacks, and validation rules all live here — any developer reading the file immediately sees what the model relates to, what triggers fire, and what rules apply.

```jda
// app/models/post.jda
fn post_model_init() {
    forge_model("posts")

    // Associations
    forge_assoc_belongs_to("user",     "users",    "user_id")
    forge_assoc_has_many  ("comments", "comments", "post_id")
    forge_assoc_has_one   ("image",    "images",   "post_id")

    // Callbacks
    forge_callback(FORGE_CB_BEFORE_SAVE,  fn_addr(post_before_save))
    forge_callback(FORGE_CB_AFTER_CREATE, fn_addr(post_after_create))

    // Validations
    forge_field       ("title, body, author", FORGE_V_PRESENCE)
    forge_field_length("title",               2, 255)
    forge_field_min   ("body",                10)
    forge_field       ("email",               FORGE_V_EMAIL)
    forge_field_param ("status",              FORGE_V_INCLUSION, "draft,published,archived")
}
```

`forge generate model` scaffolds this pattern automatically: the init function with `forge_assoc_belongs_to` for any `references` field, commented-out callback stubs, and `forge_field` lines for all validatable columns.

Typed accessor functions (`post_user`, `post_comments`, etc.) are **not** hand-written — `forge compile-models` reads the `forge_assoc_*` declarations in your model file and generates them into `_build/models.jda` on every build. Add a `forge_assoc_*` line, run `forge build`, and the accessor is ready.

Call the init function once at startup — typically in `main.jda` before `routes(app)`:

### Declarative validations

Register rules once at startup. They fire automatically inside every `post_create` and `post_update` call — you never call them in the controller.

Call `forge_model(table)` once at the top of your init function to set the model context, then use the short `forge_field*` helpers — no need to repeat the table name on every line:

```jda
post_model_init()
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

#### Validation reference

| Forge (declarative) | Notes |
|---|---|
| `forge_field("f", FORGE_V_PRESENCE)` | |
| `forge_field("f", FORGE_V_ABSENCE)` | |
| `forge_field("f, g", FORGE_V_PRESENCE)` | comma-separated |
| `forge_field_min("f", 2)` | |
| `forge_field_param("f", FORGE_V_MAX_LEN, "255")` | |
| `forge_field_length("f", 2, 255)` | |
| `forge_field_exact("f", 10)` | |
| `forge_field("f", FORGE_V_NUMERICALITY)` | digits only |
| `forge_field_gt("f", 0)` | |
| `forge_field_gte("f", 18)` | |
| `forge_field_lt("f", 100)` | |
| `forge_field_lte("f", 65)` | |
| `forge_field_equal_to("f", 42)` | |
| `forge_field("f", FORGE_V_EMAIL)` | |
| `forge_field("f", FORGE_V_URL)` | http/https + dot |
| `forge_field_param("f", FORGE_V_INCLUSION, "a,b,c")` | |
| `forge_field_param("f", FORGE_V_EXCLUSION, "admin,root")` | |
| `forge_field_acceptance("f")` | "1" or "true" |
| `forge_field_confirm("f", "f_confirmation")` | ¹ |
| `forge_validate_uniqueness(e, table, f, val, id)` | manual only ² |

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

#### Context-specific validations (create-only / update-only)

`forge_field_on_create` and `forge_field_on_update` mark the most-recently-registered rule so it only fires in one context. Call them immediately after the rule registration:

```jda
fn user_model_init() {
    forge_model("users")
    forge_field("email", FORGE_V_PRESENCE)
    forge_field("email", FORGE_V_EMAIL)

    // password required only on create; optional on profile updates
    forge_field("password", FORGE_V_PRESENCE)
    forge_field_on_create("password")

    forge_field_min("password", 8)
    forge_field_on_create("password")
}
```

| Function | Effect |
|---|---|
| `forge_field_on_create(field)` | Rule fires only when `g_forge_save_context == "create"` |
| `forge_field_on_update(field)` | Rule fires only when `g_forge_save_context == "update"` |

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

1. `FORGE_CB_BEFORE_VALIDATION` callbacks
2. Declarative validations — abort and set `forge_last_errors()` if any fail
3. `FORGE_CB_AFTER_VALIDATION` callbacks
4. `FORGE_CB_BEFORE_SAVE` callbacks
5. `FORGE_CB_BEFORE_CREATE` / `FORGE_CB_BEFORE_UPDATE` callbacks
6. SQL INSERT / UPDATE
7. On success: `FORGE_CB_AFTER_CREATE` / `FORGE_CB_AFTER_UPDATE` → `FORGE_CB_AFTER_SAVE` → `FORGE_CB_AFTER_COMMIT`
8. On DB failure: `FORGE_CB_AFTER_ROLLBACK`

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

Declare associations at the model level so the complete relationship graph is visible in one place. `forge compile-models` reads these declarations on every build and auto-generates typed accessor functions into `_build/models.jda` — no manual stubs needed.

### Declaring associations (model-level)

Inside `*_model_init`, after `forge_model()`. Forge supports the full set of associations including HABTM, polymorphic, and self-referential (parent/child).

#### belongs_to / has_many / has_one

```jda
fn post_model_init() {
    forge_model("posts")
    forge_assoc_belongs_to("user",     "users",    "user_id")   // parent record
    forge_assoc_has_many  ("comments", "comments", "post_id")   // children
    forge_assoc_has_one   ("image",    "images",   "post_id")   // single child
}
```

#### has_many :through (HABTM)

Many-to-many through a join table:

```jda
fn post_model_init() {
    forge_model("posts")
    forge_assoc_has_many_through("tags", "tags", "post_tags", "post_id", "tag_id")
    //                           name  target  join_table  owner_fk  target_fk
}

fn tag_model_init() {
    forge_model("tags")
    forge_assoc_has_many_through("posts", "posts", "post_tags", "tag_id", "post_id")
}
```

#### Polymorphic associations

A `belongs_to :commentable, polymorphic: true` pattern — a single model can belong to any number of other model types via a type/id column pair:

```jda
fn comment_model_init() {
    forge_model("comments")
    // "commentable_type" stores "Post", "Video", etc.
    // "commentable_id"   stores the owner's id
    forge_assoc_poly_belongs_to("commentable", "commentable_type", "commentable_id")
}

fn post_model_init() {
    forge_model("posts")
    forge_assoc_poly_has_many("comments", "comments", "commentable_id", "commentable_type", "Post")
    //                         name       target       fk_id             fk_type             type_val
}
```

#### Self-referential (parent/child)

Hierarchical data uses the same `forge_assoc_belongs_to` / `forge_assoc_has_many` with the same table:

```jda
fn category_model_init() {
    forge_model("categories")
    forge_assoc_belongs_to("parent",   "categories", "parent_id")
    forge_assoc_has_many  ("children", "categories", "parent_id")
}
```

---

### Auto-generated accessor functions

`forge compile-models` (runs automatically on `forge server` / `forge build`) reads every `forge_assoc_*` declaration in your `app/models/*.jda` files and emits typed accessor functions into `_build/models.jda`. You never write these by hand.

Given the declarations above, `_build/models.jda` will contain:

```jda
// Standard / through / poly has_many — one argument
fn post_user(fk_val: []i8)      -> &ForgeResult { ret forge_assoc_query("posts", "user",     fk_val) }
fn post_comments(post_id: []i8) -> &ForgeResult { ret forge_assoc_query("posts", "comments", post_id) }
fn post_tags(post_id: []i8)     -> &ForgeResult { ret forge_assoc_query("posts", "tags",     post_id) }

// Polymorphic belongs_to — two arguments (type value + id from the row)
fn comment_commentable(type_val: []i8, id_val: []i8) -> &ForgeResult {
    ret forge_assoc_poly_query("comments", "commentable", type_val, id_val)
}
```

Call them from controllers or other models:

```jda
let author   = post_user(post.user_id)
let comments = post_comments(post.id)
let tags     = post_tags(post.id)
let owner    = comment_commentable(comment.commentable_type, comment.commentable_id)
```

### Ad-hoc association queries

For one-off lookups without a declared association, call the underlying helpers directly:

```jda
let user    = forge_belongs_to("users", post.user_id)
let posts   = forge_has_many("posts", "user_id", uid)
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

### Registering callbacks (model-level)

Declare callbacks inside `*_model_init` after `forge_model()` using `forge_callback`. This keeps the entire model definition — associations, callbacks, validations — visible in one function:

```jda
fn user_model_init() {
    forge_model("users")

    forge_callback(FORGE_CB_BEFORE_SAVE,   fn_addr(user_hash_password))
    forge_callback(FORGE_CB_AFTER_CREATE,  fn_addr(user_send_welcome_email))
    forge_callback(FORGE_CB_BEFORE_DELETE, fn_addr(user_cancel_subscriptions))

    forge_field("email, password", FORGE_V_PRESENCE)
    forge_field("email",           FORGE_V_EMAIL)
}
```

`forge_callback` uses the model set by the preceding `forge_model()` call — no need to repeat the table name.

### Callback function signature

```jda
fn user_hash_password(row_ptr: i64) -> bool {
    // row_ptr is a pointer to the row struct in memory
    // Return false to abort the save
    ret true
}
```

### Registering callbacks explicitly

If you need to register callbacks outside the model init (e.g. in a plugin or library):

```jda
forge_callback_add("users", FORGE_CB_BEFORE_SAVE,   fn_addr(user_hash_password))
forge_callback_add("users", FORGE_CB_AFTER_CREATE,  fn_addr(user_send_welcome_email))
```

### Available callback constants

| Constant | Fires |
|---|---|
| `FORGE_CB_BEFORE_VALIDATION` | Before declarative validations run |
| `FORGE_CB_AFTER_VALIDATION` | After declarative validations run (even if validation failed) |
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

Forge lets you register filter functions that run before selected controller actions. The filter loads shared data (e.g. the current post) into the request context via `ctx_set`; actions read it back with `ctx_get`.

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
    post_model_init()
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
| `forge_ctrl_before_except(ctrl, fn_ptr, except)` | Register a before filter that runs for **all** actions except those listed. |
| `forge_ctrl_after(ctrl, fn_ptr, only)` | Register an after filter. |
| `forge_ctrl_register(name, ctrl)` | Bind the controller to a resource name (e.g. `"posts"`). |
| `ctx_set(ctx, key, val)` | Store an `i64` value on the request context. |
| `ctx_get(ctx, key) -> i64` | Retrieve a stored value; cast to the original type with `as`. |

### only / except — matching rules

`forge_ctrl_before` uses an `only` list:
- `""` — fires for every action
- `"show"` — exact match
- `"show, edit, update, delete"` — comma-separated, spaces optional

`forge_ctrl_before_except` uses an `except` list and fires for every action **not** in the list:

```jda
fn posts_before_actions() {
    let ctrl = forge_ctrl_new()
    // Set post for everything except index and new
    forge_ctrl_before_except(ctrl, fn_addr(posts_set_post), "index, new, create")
    forge_ctrl_register("posts", ctrl)
}
```

---

## Soft Delete

All generated tables include a `deleted_at TIMESTAMP` column. The soft delete helpers set or clear this column instead of removing rows.

### Soft-deleting a row

```jda
let ok = forge_soft_delete("posts", id)
let ok = post_delete(id)    // generated wrapper
```

Sets `deleted_at = NOW()`. Generated finders (`post_q`, `post_all`, `post_find`, etc.) exclude soft-deleted rows automatically when the table has a `deleted_at` column.

### Restoring a soft-deleted row

```jda
let ok = forge_restore("posts", id)
```

Sets `deleted_at = NULL`, making the row visible again.

### Hard-deleting a row (with callbacks)

```jda
let ok = forge_hard_delete("posts", id)     // fires BEFORE/AFTER_DELETE + AFTER_COMMIT
let ok = post_destroy(id)                   // generated wrapper
```

Fires the full `BEFORE_DELETE` → SQL → `AFTER_DELETE` → `AFTER_COMMIT` callback lifecycle.

### Hard-deleting a row (no callbacks)

```jda
let ok = forge_purge("posts", id)           // raw DELETE, skips all callbacks
```

Permanently removes the row without firing any callbacks. Use `forge_destroy` when you need callbacks to run.

### Querying deleted rows

Use the helpers that are generated automatically for tables with `deleted_at`, or call the low-level functions directly:

```jda
// Generated per-table helpers (preferred)
let with_trash   = post_with_deleted().exec()           // all rows including deleted
let trash_only   = post_only_deleted().order_desc("deleted_at").exec()

// Low-level, for ad-hoc queries
let q = forge_q_with_deleted(forge_q("posts"))          // include deleted
let q = forge_q_only_deleted(forge_q("posts"))          // only deleted
let q = forge_q_where_not_deleted(forge_q("posts"))     // explicit IS NULL filter
let q = forge_q_unscope(forge_q("posts"))               // drop filter + ORDER BY
```

| Function | SQL effect |
|---|---|
| `forge_q_where_not_deleted(q)` | Adds `WHERE deleted_at IS NULL` |
| `forge_q_with_deleted(q)` | Removes the soft-delete filter |
| `forge_q_only_deleted(q)` | Adds `WHERE deleted_at IS NOT NULL` |
| `forge_q_unscope(q)` | Removes soft-delete filter and ORDER BY |

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

### forge_reload

Re-fetches a record from the database by id. Bypasses soft-delete scoping — works even on deleted rows.

```jda
let fresh = forge_reload("posts", id)
let fresh = post_reload(id)    // generated wrapper
```

### forge_toggle

Flips a boolean column with `SET col = NOT col`. Bypasses validations and callbacks.

```jda
forge_toggle("posts", id, "published")
post_toggle(id, "published")    // generated wrapper
```

### forge_increment / forge_decrement

Atomically adds or subtracts `by` from a numeric column. Bypasses validations and callbacks.

```jda
forge_increment("posts", id, "view_count", 1)
forge_decrement("products", id, "stock", qty)

post_increment(id, "view_count", 1)    // generated wrapper
post_decrement(id, "stock",      qty)  // generated wrapper
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

## Multiple Databases

Forge supports multiple named database connections in a single app. Connections are registered at startup by URL and can target different database servers — including a mix of PostgreSQL and MySQL/MariaDB.

### Supported databases

| URL scheme | Database |
|---|---|
| `postgres://` / `postgresql://` | PostgreSQL 12+ |
| `mysql://` / `mariadb://` | MySQL 5.7+ / MariaDB 10.3+ |

### Registering connections

In `config/application.jda`, add connections inside `app_config`:

```jda
fn app_config() -> ForgeConfig {
    let cfg = forge_default_config()
    forge_db_add("primary",   forge_env_get("DATABASE_URL"))
    forge_db_add("analytics", forge_env_get("ANALYTICS_DATABASE_URL"))
    forge_db_add("warehouse", forge_env_get("WAREHOUSE_DATABASE_URL"))
    // ...
    ret cfg
}
```

The first registered connection (`"primary"`) is the default for all queries.

### Binding a model to a connection

Declare the connection inside the model's validations init with `forge_model_db`. Every generated helper for that table (`event_all`, `event_find`, `event_q`, `event_create`, etc.) will automatically route through that connection — no per-call changes needed.

```jda
fn event_model_init() {
    forge_model("events")
    forge_model_db("analytics")          // all event_* queries use "analytics"
    forge_field("name, type", FORGE_V_PRESENCE)
}
```

Models without a `forge_model_db` call use the primary connection.

### Ad-hoc queries on a specific connection

Use `forge_q_on(conn_name, table)` when you need a one-off query against a different connection without declaring a model-level binding:

```jda
// One-off analytics query
forge_q_on("analytics", "events")
    .where_eq("type", "click")
    .order_desc("created_at")
    .limit(100)
    .exec()

// Scalar aggregate on the warehouse
forge_q_on("warehouse", "sales").sum("amount")
```

### Switching the active connection

`forge_db_use` sets the default connection for the current goroutine's subsequent unscoped `forge_db_query` / `forge_db_exec` calls:

```jda
forge_db_use("analytics")
forge_db_exec("INSERT INTO events ...")
forge_db_use("primary")
```

### Raw queries on a specific connection

```jda
forge_db_query_on(forge_db_conn_idx("analytics"), "SELECT COUNT(*) FROM events")
forge_db_exec_on(forge_db_conn_idx("warehouse"),  "TRUNCATE staging_table")
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

### Migration file format

Every generated migration has two sections:

```sql
-- migrate:up
CREATE TABLE posts (
    id         BIGSERIAL PRIMARY KEY,
    title      VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP
);

-- migrate:down
DROP TABLE IF EXISTS posts;
```

`forge db:migrate` runs only the `-- migrate:up` section. `forge db:rollback` runs the `-- migrate:down` section. Files without a `-- migrate:down` marker are treated as up-only (legacy format — the entire file runs on migrate, rollback is blocked).

### Running migrations

```bash
forge db:migrate
forge db:migrate --environment production
```

Reads `db/migrate/*.sql` in order, checks each filename against the `forge_migrations` tracking table, and runs any `-- migrate:up` sections that haven't been applied yet. Safe to run repeatedly.

### Rolling back

```bash
forge db:rollback                    # undo the last migration
forge db:rollback --step 3           # undo the last 3 migrations
forge db:rollback --version 002      # rollback until only migrations ≤ 002 remain
forge db:rollback --environment staging
```

Each rollback runs the `-- migrate:down` section of the target migration and removes it from the `forge_migrations` tracking table.

```bash
forge db:status          # show ran vs. pending
```

Migrations also run automatically at application startup via `forge_migration_run("db/migrate")` in `main.jda`. Use `forge db:migrate` when you want to apply migrations without restarting the server (CI, deployment scripts, one-off tasks).

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

---

## Counter Caches

A counter cache keeps a running count of a child table's rows on the parent row — so showing a comment count on a post doesn't require an extra `COUNT(*)` query.

### Declaring a counter cache

Call `forge_counter_cache` inside the **child** model's `*_model_init`:

```jda
fn comment_model_init() {
    forge_model("comments")
    forge_counter_cache("comments", "post_id", "posts", "comments_count")
    // ...
}
```

Arguments: `(child_table, foreign_key_col, parent_table, counter_column)`

### Migration

Add the counter column to the parent table with a default of 0:

```sql
ALTER TABLE posts ADD COLUMN comments_count INTEGER NOT NULL DEFAULT 0;
```

### How it works

Forge hooks into `forge_attrs_insert` and `forge_soft_delete`. When a comment is created the parent row's `comments_count` is incremented with a single `UPDATE`. When it is soft-deleted, the count is decremented. Hard deletes (`forge_hard_delete`) do not update the counter — manage those manually if needed.

### Resetting a stale counter

```jda
forge_counter_cache_reset("comments")
// Issues: UPDATE posts p SET comments_count = (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id)
```

### Using the count in a view

```jda
<p><%== post.comments_count %> comment(s)</p>
```

---

## Dirty Tracking

Dirty tracking lets you check whether a column value has changed since the record was loaded. It is built on the in-process cache (`forge_cache`) and is opt-in per column.

### Snapshot the original value

Call `forge_dirty_load_result` right after loading a record. Pass the table name, the record's id, the `&ForgeResult`, and the column name to snapshot:

```jda
fn posts_update(ctx: i64) {
    let id   = ctx_param(ctx, "id")
    let post = post_find(id)
    forge_dirty_load_result("posts", id, post, "title")   // snapshot original title
    // ...
}
```

### Check for changes

```jda
let new_title = ctx_param(ctx, "title")
if forge_dirty_changed("posts", id, "title", new_title) {
    forge_log_ctx_info(ctx, "post title changed")
}
```

`forge_dirty_changed(table, id, col, current_val)` returns `true` when `current_val` differs from the snapshotted original.

### Read the original value

```jda
let original_title = forge_dirty_was("posts", id, "title")
```

### API

| Function | Description |
|---|---|
| `forge_dirty_load_result(table, id, res, col)` | Snapshot `res[0].col` as the original value |
| `forge_dirty_was(table, id, col)` | Return the snapshotted original value |
| `forge_dirty_changed(table, id, col, current)` | `true` if current differs from original |
| `forge_dirty_set(table, id, col, orig_val)` | Manually set an original value |

---

## Single Table Inheritance (STI)

STI stores multiple model types in one table, differentiated by a type column. One migration, one table, subtype-scoped query helpers generated by `forge compile-models`.

### Schema

Add a `type` column (or any name) to the shared table:

```sql
CREATE TABLE vehicles (
    id         SERIAL PRIMARY KEY,
    type       VARCHAR(64) NOT NULL,
    make       VARCHAR(255),
    model      VARCHAR(255),
    horsepower INTEGER,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);
```

### Model files

Create one file per subtype. Use `forge_sti_subtype` instead of `forge_model` — it redirects all subsequent `forge_field` and `forge_callback` calls to the parent table:

```jda
// app/models/car.jda
fn car_model_init() {
    forge_sti_subtype("vehicles", "type", "Car")
    forge_field("make, model", FORGE_V_PRESENCE)
}

// app/models/truck.jda
fn truck_model_init() {
    forge_sti_subtype("vehicles", "type", "Truck")
    forge_field("make, model", FORGE_V_PRESENCE)
}
```

Register both in `main()`:

```jda
car_model_init()
truck_model_init()
```

### Generated helpers

`forge compile-models` emits a full set of type-scoped functions for each subtype. Every query automatically includes `WHERE type = 'Car'`:

| Function | Description |
|---|---|
| `car_all()` | All Cars, ordered by created_at DESC |
| `car_find(id)` | Find a Car by id |
| `car_find_by(col, val)` | Find first Car matching a column |
| `car_where(col, val)` | Returns a `ForgeQuery` pre-filtered for Cars |
| `car_q()` | Bare `ForgeQuery` pre-filtered for Cars |
| `car_count()` | Count Cars |
| `car_exists(id)` | Existence check |
| `car_create_from(attrs)` | INSERT with `type='Car'` stamped automatically |
| `car_delete(id)` | Soft-delete on the shared table |
| `car_row(result, r)` | Delegates to `vehicle_row` — returns `&VehicleRow` |

If the parent table has `deleted_at`, `car_with_deleted()` and `car_only_deleted()` are also generated.

---

## Enum Helpers

Enum helpers convert between a column value and a human-readable label. They are pure in-process lookups — no special column type needed.

```jda
let STATUSES = "draft, published, archived"

fn post_status_label(status_val: []i8) -> []i8 {
    ret forge_enum_name(forge_enum_val(status_val, STATUSES) as i64, STATUSES)
}
```

| Function | Description |
|---|---|
| `forge_enum_val(name, vals_csv)` | Position (0-based) of `name` in the CSV list |
| `forge_enum_name(idx, vals_csv)` | Label at position `idx` in the CSV list |

Example — storing an integer index and displaying the label:

```jda
// Store: save status index as a string
let idx = forge_enum_val("published", STATUSES)   // "1"
forge_update_column("posts", id, "status_idx", idx)

// Display: convert back to label
let label = forge_enum_name(str_to_i64(post.status_idx), STATUSES)  // "published"
```

---

## Bulk Operations: find_or_init_by and insert_all

### forge_find_or_init_by

Returns the first row matching a column/value, or a new empty `&ForgeAttrs` if no match exists. Use it for "find or build" without committing to the database immediately:

```jda
let attrs = forge_find_or_init_by("tags", "name", "elixir")
// attrs.new is true  → not in DB yet; set more fields then call forge_attrs_insert
// attrs.new is false → found; attrs fields populated from the existing row
forge_attrs_set(attrs, "color", "#6e4494")
if attrs.new {
    forge_attrs_insert(attrs, "tags")
} else {
    forge_attrs_update(attrs, "tags", forge_attrs_get(attrs, "id"))
}
```

### forge_insert_all

Inserts multiple rows with a single SQL statement. Pass a CSV of column names and a CSV of value tuples:

```jda
forge_insert_all("tags",
    "name, color",
    "'elixir','#6e4494' | 'rust','#ce412b' | 'go','#00aed8'")
```

Rows are separated by `|`. Values must be pre-quoted (single-quoted strings, bare numbers). Returns `true` if the INSERT succeeded.
