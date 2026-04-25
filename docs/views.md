# Views

JDA Forge uses ERB-style `.html.jda` templates — HTML with embedded JDA code between `<% %>` tags. `forge compile-views` compiles them into plain JDA functions in `_build/views.jda`, which means the full language (loops, conditionals, function calls) is available, and there is zero runtime template overhead.

---

## Template syntax

```html
<% fn view_posts_index(ctx: i64, posts: &ForgeResult) %>
<%layout "Posts" %>

<%== tmpl_flash(ctx) %>
<h1>Blog Posts</h1>

<% loop r in 0..posts.count { %>
  <%== render_post_row(posts, r) %>
<% } %>
```

| Tag | Meaning | Generated code |
|---|---|---|
| `<% fn name(params) %>` | Function signature (first tag in file) | `fn name(params) -> []i8 {` |
| `<% code %>` | JDA statement — loops, if, let, ret | emitted verbatim |
| `<%= expr %>` | **HTML-escaped** output (user content) | `buf.write(forge_h(expr))` |
| `<%== expr %>` | **Raw** output (paths, partials, HTML) | `buf.write(expr)` |
| `<%layout expr %>` | Wrap in layout function | `ret tmpl_layout(expr, buf.done())` |
| `<%# comment %>` | Comment — ignored | — |

**One function per file.** Files starting with `_` are partials and may be called from any other template.

### `<%= %>` vs `<%== %>`

- Use `<%= %>` for **user-supplied content**: titles, body text, author names, form values. It calls `forge_h()` which escapes `&`, `<`, `>`, `"`, `'`.
- Use `<%== %>` for **HTML-safe values**: path helpers, partial calls, pre-built HTML strings, system-generated content like dates or IDs.

### Rendering a partial with a row object

`forge compile-models` auto-generates a typed row struct and converter for every table. For a `posts` table it produces `PostRow` and `post_row(result, r)`:

```html
<%# app/views/posts/_post.html.jda %>
<% fn tmpl_post_row(post: &PostRow) %>
<div class="post">
  <h2><a href="<%== post_path(post.id) %>"><%= post.title %></a></h2>
  <p class="meta">by <%= post.author %> on <%== post.created_at %></p>
</div>
```

```html
<%# app/views/posts/index.html.jda — call with post_row() %>
<% loop r in 0..posts.count { %>
<%== tmpl_post_row(post_row(posts, r)) %>
<% } %>
```

`post_row(posts, r)` extracts row `r` from a `&ForgeResult` and returns a `&PostRow` with every column as a field. Similarly `comment_row(comments, r)` returns `&CommentRow`.

Use `post_row(result, 0)` in show/edit views to get a single row object:

```html
<% let p = post_row(post, 0) %>
<%layout p.title %>
<h1><%= p.title %></h1>
<p><%= p.body %></p>
```

---

## Table of Contents

1. [HTML-escape helpers](#1-html-escape-helpers)
2. [Form helpers](#2-form-helpers)
3. [Link helpers](#3-link-helpers)
4. [Layout pattern](#4-layout-pattern)
5. [Reading query results in views](#5-reading-query-results-in-views)
6. [Partials](#6-partials)
7. [JSON serialization](#7-json-serialization)
8. [Flash messages](#8-flash-messages)
9. [Security: always escape user content](#9-security-always-escape-user-content)
10. [Form builder with model binding](#10-form-builder-with-model-binding)
11. [Text helpers: highlight and excerpt](#11-text-helpers-highlight-and-excerpt)

---

## 1. HTML-escape helpers

Always escape user-supplied values before embedding them in HTML output.

### forge_h

Inline escape for use directly inside an HTML string. Escapes `&`, `<`, `>`, `"`, and `'`.

```jda
let safe = forge_h(user_title)
ctx_html(ctx, 200, "<h1>" + safe + "</h1>")
```

This is the function to reach for in almost every case.

### forge_html_escape

Low-level version that writes into a caller-supplied buffer. Returns the number of bytes written.

```jda
let buf: &i8 = alloc_pages(1)
let n = forge_html_escape(user_input, buf)
let escaped = buf[0..n]
```

Use `forge_html_escape` when you are building output into a buffer manually and want to avoid the intermediate allocation that `forge_h` produces.

---

## 2. Form helpers

### Opening and closing a form

`forge_form_tag_open` generates a `<form>` element with the CSRF token baked in as a hidden field.

```jda
let token = forge_csrf_token(ctx)
forge_form_tag_open("/posts", "POST", token)
// → <form action="/posts" method="POST">
//       <input type="hidden" name="_csrf" value="...">

forge_form_tag_close()
// → </form>
```

Always obtain the token from the request context with `forge_csrf_token(ctx)`.

### Input fields

```jda
forge_input_tag("text",     "title",    title)
// → <input type="text" name="title" value="...">

forge_input_tag("password", "password", "")
forge_input_tag("hidden",   "redirect", "/posts")
forge_input_tag("email",    "email",    email)
```

The third argument is the current value. Values are HTML-escaped internally — do not double-escape.

### Labels

```jda
forge_label_tag("title", "Post Title")
// → <label for="title">Post Title</label>
```

### Textarea

```jda
forge_textarea_tag("body", existing_body, 8, 60)
// → <textarea name="body" rows="8" cols="60">...</textarea>
```

The content is HTML-escaped internally.

### Submit button

```jda
forge_submit_tag("Save Post")
// → <input type="submit" value="Save Post">
```

### Select dropdown

Pass a comma-separated string of options. The current value is matched and gets `selected`.

```jda
forge_select_tag("role", "admin,editor,viewer", current_role)
// → <select name="role">
//       <option value="admin" selected>admin</option>
//       <option value="editor">editor</option>
//       <option value="viewer">viewer</option>
//   </select>
```

---

## 3. Link helpers

### Anchor links

```jda
forge_link_to("View Post", "/posts/42")
// → <a href="/posts/42">View Post</a>
```

### Delete link

`forge_link_to_delete` renders a small `<form>` that sends a DELETE request. The CSRF token is included automatically.

```jda
forge_link_to_delete("Delete", "/posts/42", csrf_token)
// → <form method="POST" action="/posts/42">
//       <input type="hidden" name="_method" value="DELETE">
//       <input type="hidden" name="_csrf" value="...">
//       <button type="submit">Delete</button>
//   </form>
```

### Button to

Renders a form that submits to a URL using any HTTP method.

```jda
forge_button_to("Publish", "/posts/42/publish", "POST")
// → <form method="POST" action="/posts/42/publish">
//       <button type="submit">Publish</button>
//   </form>
```

---

## 4. Layout pattern

The layout lives in `app/views/layouts/application.html.jda`. It receives a `title` and the rendered page `body`, wraps them in the full HTML shell, and returns the complete page string.

```html
<% fn tmpl_layout(title: []i8, body: []i8) %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title><%= title %> — MyApp</title>
  <%== forge_stylesheet_tag("application.css") %>
</head>
<body>
<nav><a href="<%== posts_path %>">Posts</a></nav>
<%== body %>
<%== forge_javascript_tag("application.js") %>
</body>
</html>
```

Any view that adds `<%layout "Title" %>` automatically wraps its output in `tmpl_layout`:

```html
<% fn view_posts_index(ctx: i64, posts: &ForgeResult) %>
<%layout "Posts" %>
<%== tmpl_flash(ctx) %>
<h1>Posts</h1>
...
```

`forge compile-views` compiles this to:

```jda
fn view_posts_index(ctx: i64, posts: &ForgeResult) -> []i8 {
    let buf = forge_buf_new(8)
    buf.write(tmpl_flash(ctx))
    buf.write("<h1>Posts</h1>\n...")
    ret tmpl_layout("Posts", buf.done())
}
```

The controller calls the compiled function unchanged:

```jda
fn posts_index(ctx: i64) {
    ctx_render(ctx, view_posts_index(ctx, post_all()))
}
```

---

## 5. Reading query results in views

`compile_models` generates a typed row struct and `<table>_row()` converter for every table. Use them instead of repeated `forge_result_col` calls.

```html
<%# loop over a result set %>
<% loop r in 0..posts.count { %>
<% let p = post_row(posts, r) %>
<p><%= p.title %> by <%= p.author %></p>
<% } %>
```

For a single-row result (show/edit views), convert at the top:

```html
<% let p = post_row(post, 0) %>
<%layout p.title %>
<h1><%= p.title %></h1>
<p><%= p.body %></p>
```

`post_row(result, r)` returns a `&PostRow` struct with every column as a `[]i8` field (`id`, `title`, `body`, `author`, `created_at`, `updated_at`, `deleted_at`). The struct and function are auto-generated into `_build/models.jda` from the migration schema — no manual maintenance.

`forge_result_col` is still available if you need a single column without converting the whole row.

---

## 6. Partials

Partials are `.html.jda` template files whose names start with `_`. They are compiled into ordinary JDA functions by `forge compile-views` and can be called from any other template.

### Defining a partial

```html
<%# app/views/posts/_post.html.jda %>
<% fn tmpl_post_row(post: &PostRow) %>
<div class="post">
  <h2><a href="<%== post_path(post.id) %>"><%= post.title %></a></h2>
  <p class="meta">by <%= post.author %> on <%== post.created_at %></p>
</div>
```

### Calling a partial

Use `<%== %>` (raw) to call the partial function and embed its output:

```html
<% loop r in 0..posts.count { %>
<%== tmpl_post_row(post_row(posts, r)) %>
<% } %>
```

Arguments map directly to the partial's function parameters. There is no implicit locals hash — the signature is the contract, and mismatches are caught at compile time.

### Partial for a single item (show/edit)

```html
<% let p = post_row(post, 0) %>
<%== render_post_form(post_path(p.id), p.title, p.body, forge_csrf_token(ctx), "Update") %>

---

## 7. JSON serialization

These functions are useful in API controllers and in views that embed JSON into JavaScript.

### Serialize a full result set to a JSON array

```jda
let json = forge_result_to_json(res)
// → '[{"id":"1","title":"Hello",...}, ...]'
```

### Serialize a single row to a JSON object

```jda
let json = forge_row_to_json(res, 0)
// → '{"id":"1","title":"Hello",...}'
```

The second argument is the zero-based row index.

### Escape a value for embedding in a JSON string

```jda
let safe = forge_json_escape(user_content)
let json = "{\"title\":\"" + safe + "\"}"
```

Use `forge_json_escape` when building JSON strings manually. It escapes `"`, `\`, and control characters.

---

## 8. Flash messages

Flash messages survive exactly one redirect. They are stored in the session by a handler, then read and cleared on the following request.

### Setting a flash in a handler

```jda
ctx_flash_set(ctx, "notice", "Post created.")
ctx_flash_set(ctx, "alert",  "Email is invalid.")
ctx_redirect(ctx, "/posts")
```

### Reading a flash in the layout

```jda
let msg = ctx_flash_get(ctx, "notice")
if msg.len > 0 {
    // render msg inside a notice div
}
```

Conventions used throughout Forge:

| Key | Meaning |
|---|---|
| `notice` | Success or informational message |
| `alert` | Error or warning |

The session middleware (`forge_session_start`) must be registered for flash messages to work.

---

## 9. Security: always escape user content

Failing to escape user-supplied values is the most common source of XSS vulnerabilities. The rule is simple: escape at the point of output, every time.

| Situation | Function |
|---|---|
| User content in an HTML text node | `forge_h(val)` |
| User content in an HTML attribute value | `forge_h(val)` |
| User content in a JSON string value | `forge_json_escape(val)` |
| Building a URL from user input | `forge_h(val)` on the final URL; also validate the scheme |
| Value read from the database | Still escape — the database does not sanitize on write |

Forge's form helpers (`forge_input_tag`, `forge_textarea_tag`, `forge_select_tag`) escape values internally. Values produced by `forge_result_col` are raw strings from the database and must be escaped before use in HTML.

---

## 10. Form builder with model binding

The form builder helpers emit a complete `<label>` + `<input>` (or `<textarea>`, `<select>`) block in one call, pre-populated with a current value. They escape all values automatically.

### forge_field_tag

Renders a labelled text input:

```jda
<%== forge_field_tag("title", "Title", post.title) %>
```

Output:

```html
<div class="field">
  <label for="title">Title</label>
  <input type="text" id="title" name="title" value="Hello World">
</div>
```

### forge_field_tag_type

Same as `forge_field_tag` but lets you specify the `<input type>`:

```jda
<%== forge_field_tag_type("email", "Email address", "email", user.email) %>
<%== forge_field_tag_type("password", "Password", "password", "") %>
```

### forge_textarea_field_tag

Renders a labelled `<textarea>`:

```jda
<%== forge_textarea_field_tag("body", "Body", post.body, 10, 60) %>
```

Arguments: `(col, label, current_val, rows, cols)`

### forge_select_field_tag

Renders a labelled `<select>` dropdown. The options string is a CSV of `value:Label` pairs (or bare `value` if the label matches):

```jda
<%== forge_select_field_tag("status", "Status", "draft:Draft, published:Published, archived:Archived", post.status) %>
```

The option whose value matches `current_val` gets `selected`.

### Full form example

```jda
<% fn view_posts_edit(ctx: i64, post: &ForgeResult) %>
<% let p = post_row(post, 0) %>
<%layout "Edit Post" %>
<h1>Edit Post</h1>
<form method="POST" action="<%== post_path(p.id) %>">
  <input type="hidden" name="_method" value="PUT">
  <%== forge_field_tag("title", "Title", p.title) %>
  <%== forge_textarea_field_tag("body", "Body", p.body, 10, 60) %>
  <%== forge_field_tag("author", "Author", p.author) %>
  <input type="hidden" name="_csrf" value="<%= forge_csrf_token(ctx) %>">
  <button>Update</button>
</form>
```

### API

| Function | Description |
|---|---|
| `forge_field_tag(col, label, val)` | Labelled text input |
| `forge_field_tag_type(col, label, type, val)` | Labelled input with custom type |
| `forge_textarea_field_tag(col, label, val, rows, cols)` | Labelled textarea |
| `forge_select_field_tag(col, label, options_csv, val)` | Labelled select dropdown |

---

## 11. Text helpers: highlight and excerpt

### forge_excerpt

Returns a short window of text around a phrase, suitable for search result snippets or post previews. Appends `...` when truncated.

```jda
let preview = forge_excerpt(post.body, "search term", 100)
// Returns up to 100 chars on each side of "search term", or just the first 200 chars
// if the phrase is not found.
```

Arguments: `(source, phrase, radius)` where `radius` is the number of characters to include on each side.

### forge_highlight

Wraps every occurrence of a phrase in an HTML tag. Useful for search result highlighting.

```jda
let highlighted = forge_highlight(post.title, query, "mark")
// <mark>Rails</mark>-style routing
```

Arguments: `(source, phrase, tag_name)`

### In templates

```jda
<p class="excerpt"><%== forge_excerpt(post.body, "", 150) %></p>
<h2><%== forge_highlight(post.title, search_query, "strong") %></h2>
```
