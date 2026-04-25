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
9. [Soft Delete](#soft-delete)
10. [Transactions](#transactions)
11. [Serialization](#serialization)
12. [Migrations](#migrations)

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
models/post.jda              — generated query functions
db/migrations/001_create_posts.sql  — migration (numbered automatically)
```

### Generated migration

```sql
-- db/migrations/001_create_posts.sql
CREATE TABLE posts (
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

### Generated model file

```jda
// models/post.jda — generated, extend by adding functions below

fn post_q() -> &ForgeQuery {
    ret forge_q("posts")
}

fn post_all() -> &ForgeResult {
    ret forge_q("posts").order_desc("created_at").exec()
}

fn post_find(id: []i8) -> &ForgeResult {
    ret forge_find("posts", id)
}

fn post_find_by(col: []i8, val: []i8) -> &ForgeResult {
    ret forge_find_by("posts", col, val)
}

fn post_where(col: []i8, val: []i8) -> &ForgeQuery {
    ret forge_q("posts").where_eq(col, val)
}

fn post_count() -> i64 {
    ret forge_q_count(forge_q("posts"))
}

fn post_exists(id: []i8) -> bool {
    ret forge_q("posts").where_eq("id", id).exists()
}

fn post_delete(id: []i8) -> bool {
    ret forge_soft_delete("posts", id)
}

fn post_validate(title: []i8, body: []i8) -> &ForgeErrors {
    let e = forge_errors_new()
    forge_validate_presence(e, "title", title)
    forge_validate_length(e, "title", title, 2, 255)
    forge_validate_presence(e, "body", body)
    ret e
}
```

---

## Generated Query Interface

The generator produces a small set of named functions per model. These cover the most common operations and serve as the starting point for all queries.

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

### post_validate

Runs field validations and returns a `&ForgeErrors`. See [Validations](#validations) for full details.

```jda
let errs = post_validate(title, body)
if forge_errors_any(errs) {
    ctx_unprocessable(ctx, forge_errors_json(errs))
    ret
}
```

### Extending the generated interface

Add your own functions to `models/post.jda` below the generated block. These are plain Jda functions and can use any query builder method.

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
    let i = 0
    loop i in 0..forge_result_len(res) {
        let row = forge_result_row(res, i)
        // process row...
    }
}

forge_find_in_batches("users", 500, fn_addr(process_batch))
```

The second argument is the batch size. `forge_find_in_batches` issues multiple queries internally, ordering by `id ASC` and using keyset pagination.

---

## Validations

Validations check field values before a record is saved. The generated `post_validate` function is the conventional place to put them, but you can call the forge validation helpers anywhere.

### Creating an error bag

```jda
let e = forge_errors_new()
```

### Available validators

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

### Checking and rendering errors

```jda
fn create_post(ctx: &ForgeCtx, title: []i8, body: []i8) {
    let errs = post_validate(title, body)
    if forge_errors_any(errs) {
        ctx_unprocessable(ctx, forge_errors_json(errs))
        ret
    }
    // proceed to insert...
}
```

`forge_errors_json` returns a JSON object mapping field names to arrays of error messages:

```json
{
  "title": ["can't be blank", "is too short (minimum 2 characters)"],
  "body": ["can't be blank"]
}
```

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

### Registering a callback

```jda
forge_callback_add("users", CB_BEFORE_SAVE,   fn_addr(hash_password_before_save))
forge_callback_add("users", CB_AFTER_CREATE,  fn_addr(send_welcome_email))
forge_callback_add("users", CB_BEFORE_DELETE, fn_addr(cancel_subscriptions))
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
| `CB_BEFORE_SAVE` | Before any INSERT or UPDATE |
| `CB_AFTER_SAVE` | After any INSERT or UPDATE |
| `CB_BEFORE_CREATE` | Before INSERT only |
| `CB_AFTER_CREATE` | After INSERT only |
| `CB_BEFORE_UPDATE` | Before UPDATE only |
| `CB_AFTER_UPDATE` | After UPDATE only |
| `CB_BEFORE_DELETE` | Before soft or hard delete |
| `CB_AFTER_DELETE` | After soft or hard delete |

### Notes

- Multiple callbacks can be registered for the same table and event; they fire in registration order.
- `update_all` and `delete_all` do not trigger callbacks.
- A before-callback returning `false` prevents the operation and stops the callback chain.

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

### Hard-deleting a row

```jda
let ok = forge_purge("posts", id)
```

Permanently removes the row from the database. Bypasses soft delete entirely.

### Querying deleted rows

`forge_q` always appends `WHERE deleted_at IS NULL`. To include soft-deleted rows, use `.where_raw` to override:

```jda
// Include deleted rows
let res = forge_q("posts").where_raw("1=1").exec()

// Only deleted rows
let res = forge_q("posts").where_not_null("deleted_at").where_raw("deleted_at IS NOT NULL").exec()
```

---

## Transactions

Use transactions when multiple writes must succeed or fail together. Forge transactions use a file descriptor as the transaction handle.

### Basic transaction pattern

```jda
let fd = forge_tx_begin()
if fd < 0 {
    // could not open transaction — handle error
    ret
}

let ok = forge_tx_exec(fd, "UPDATE accounts SET balance = balance - 100 WHERE id = '42'")
if !ok {
    forge_tx_rollback(fd)
    ret
}

let ok2 = forge_tx_exec(fd, "UPDATE accounts SET balance = balance + 100 WHERE id = '99'")
if !ok2 {
    forge_tx_rollback(fd)
    ret
}

forge_tx_commit(fd)
```

### API

| Function | Description |
|---|---|
| `forge_tx_begin() -> i64` | Starts a transaction. Returns a file descriptor, or `-1` on failure. |
| `forge_tx_exec(fd, sql) -> bool` | Executes a SQL statement in the transaction. Returns `false` on error. |
| `forge_tx_commit(fd)` | Commits the transaction and closes the descriptor. |
| `forge_tx_rollback(fd)` | Rolls back the transaction and closes the descriptor. |

### Notes

- Always rollback on any failure before returning.
- `forge_tx_exec` takes raw SQL. Do not interpolate user input without escaping.
- Transactions are not compatible with `forge_q` at this time; use raw SQL strings with `forge_tx_exec`.

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

### Typical controller usage

```jda
fn handle_post_show(ctx: &ForgeCtx, id: []i8) {
    let res = post_find(id)
    if forge_result_len(res) == 0 {
        ctx_not_found(ctx)
        ret
    }
    ctx_json(ctx, forge_row_to_json(res, 0))
}

fn handle_posts_index(ctx: &ForgeCtx) {
    let res = post_all()
    ctx_json(ctx, forge_result_to_json(res))
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
