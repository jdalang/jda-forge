# JSON Serializers

Forge has two levels of JSON rendering:

- **Auto-serialize** — one line, all columns, no configuration
- **Serializer functions** — declare exactly what to expose, add computed fields, apply conditions

---

## Auto-serialize (all columns)

```jda
fn api_posts_index(ctx: i64) {
    ctx_json_result(ctx, post_all())      // array of all rows, all columns
}

fn api_post_show(ctx: i64) {
    ctx_json_row(ctx, post_find(ctx_param(ctx, "id")))  // single object
}
```

`ctx_json_result` and `ctx_json_row` serialize every column the query returned. Use this for internal APIs or when you control the consumer.

---

## Serializer functions

For public APIs, create `app/serializers/post_serializer.jda`. The convention is:
- `post_serialize(res, r)` — single row at index `r`
- `posts_serialize(res)` — full collection

```jda
// app/serializers/post_serializer.jda

fn post_serialize(res: &ForgeResult, r: i64) -> []i8 {
    ret forge_json_new()
        .field("id",         forge_result_col(res, r, "id"))
        .field("title",      forge_result_col(res, r, "title"))
        .field("body",       forge_result_col(res, r, "body"))
        .field("created_at", forge_result_col(res, r, "created_at"))
        .done()
        // deleted_at, internal_notes — not included
}

fn posts_serialize(res: &ForgeResult) -> []i8 {
    let a = forge_json_array_new()
    loop r in 0..res.count {
        a.push(post_serialize(res, r))
    }
    ret a.done()
}
```

Use in a controller:

```jda
fn api_posts_index(ctx: i64) {
    ctx_json(ctx, 200, posts_serialize(post_all()))
}

fn api_post_show(ctx: i64) {
    let post = post_find(ctx_param(ctx, "id"))
    if post.count == 0 { ctx_not_found(ctx)  ret }
    ctx_json(ctx, 200, post_serialize(post, 0))
}
```

---

## Computed fields

Add any derived value with `.field()` — it does not have to come from the database:

```jda
fn post_serialize(res: &ForgeResult, r: i64) -> []i8 {
    let title  = forge_result_col(res, r, "title")
    let author = forge_result_col(res, r, "author")

    ret forge_json_new()
        .field("id",          forge_result_col(res, r, "id"))
        .field("title",       title)
        .field("author",      author)
        .field("display",     str_concat(title, " — ") + author)
        .field("url",         post_path(forge_result_col(res, r, "id")))
        .done()
}
```

---

## Conditional fields

Pass `ctx` to include fields based on the request:

```jda
fn post_serialize_for(res: &ForgeResult, r: i64, ctx: i64) -> []i8 {
    let j = forge_json_new()
    j.field("id",    forge_result_col(res, r, "id"))
     .field("title", forge_result_col(res, r, "title"))

    // only expose author email to admins
    if is_admin(ctx) {
        j.field("author_email", forge_result_col(res, r, "author_email"))
    }

    // only include draft body if the post is not published
    let published = forge_result_col(res, r, "published")
    if !str_eq(published, "true") {
        j.field("draft_body", forge_result_col(res, r, "body"))
    }

    ret j.done()
}
```

---

## Nested objects

Serialize related records as nested JSON using `.field_raw()`:

```jda
fn post_serialize_with_comments(res: &ForgeResult, r: i64) -> []i8 {
    let post_id  = forge_result_col(res, r, "id")
    let comments = comment_where_post(post_id)

    ret forge_json_new()
        .field("id",       post_id)
        .field("title",    forge_result_col(res, r, "title"))
        .field_raw("comments", comments_serialize(comments))
        .done()
}
```

`.field_raw(key, val)` inserts the value as-is — use it for numbers, booleans, and nested JSON arrays or objects.

---

## Reference

| Function | Description |
|---|---|
| `ctx_json_result(ctx, res)` | Render all rows + all columns as JSON array (status 200) |
| `ctx_json_row(ctx, res)` | Render first row as JSON object (status 200) |
| `forge_json_new()` | Start a JSON object builder |
| `j.field(key, val)` | Add a string field (auto-escaped) |
| `j.field_raw(key, val)` | Add a raw field (number, bool, nested JSON) |
| `j.done()` | Close and return the JSON `[]i8` |
| `forge_json_array_new()` | Start a JSON array builder |
| `a.push(obj)` | Append a JSON object string |
| `a.done()` | Close and return the JSON array `[]i8` |
