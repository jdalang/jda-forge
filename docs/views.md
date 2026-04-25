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

### Rendering a partial

Partials are just regular JDA functions. Call them with `<%== %>`:

```html
<%== tmpl_post_row(forge_result_col(posts, r, "title"), forge_result_col(posts, r, "id")) %>
```

To pass a variable from the caller, declare it in the partial's function signature:

```html
<%# app/views/posts/_post.html.jda %>
<% fn tmpl_post_row(title: []i8, id: []i8) %>
<div class="post">
  <h2><a href="<%== post_path(id) %>"><%= title %></a></h2>
</div>
```

Call it as a normal JDA function call inside `<%== %>`.

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

The standard pattern is a `layout` function that wraps a page-specific content string. The layout handles navigation, the `<head>`, and flash messages. Individual page functions build their content string and pass it to `layout`.

```jda
// views/templates.jda

fn layout(ctx: i64, title: []i8, content: []i8) -> []i8 {
    let flash_notice = ctx_flash_get(ctx, "notice")
    let flash_alert  = ctx_flash_get(ctx, "alert")
    let flash_html = ""
    if flash_notice.len > 0 {
        flash_html = "<div class=\"notice\">" + forge_h(flash_notice) + "</div>"
    }
    if flash_alert.len > 0 {
        flash_html = flash_html + "<div class=\"alert\">" + forge_h(flash_alert) + "</div>"
    }
    ret "<!DOCTYPE html><html><head><title>" + forge_h(title) + " — MyApp</title>" +
        "<link rel=\"stylesheet\" href=\"/static/app.css\"></head><body>" +
        "<nav><a href=\"/posts\">Posts</a></nav>" +
        flash_html +
        "<main>" + content + "</main>" +
        "</body></html>"
}
```

A page function builds its HTML, then passes it to `layout`:

```jda
fn posts_index_page(ctx: i64, posts: &ForgeResult) -> []i8 {
    let buf: &i8 = alloc_pages(8)
    let pos = 0i64

    let h1 = "<h1>Posts</h1><table>"
    loop i in 0..h1.len { buf[pos] = h1[i]  pos = pos + 1 }

    loop r in 0..posts.count {
        let id    = forge_result_col(posts, r, "id")
        let title = forge_result_col(posts, r, "title")
        let row = "<tr><td>" + forge_h(title) + "</td><td>" +
                  forge_link_to("View", "/posts/" + id) + "</td></tr>"
        loop i in 0..row.len { buf[pos] = row[i]  pos = pos + 1 }
    }

    let end = "</table>" + forge_link_to("New Post", "/posts/new")
    loop i in 0..end.len { buf[pos] = end[i]  pos = pos + 1 }

    ret layout(ctx, "Posts", buf[0..pos])
}
```

### Buffer sizing

`alloc_pages(n)` allocates `n * 4096` bytes. For most pages one page (4 KB) is enough; use 8 or more for pages that render large lists. There is no reallocation — size the buffer conservatively up front.

### Calling a page function from a handler

```jda
fn handle_posts_index(ctx: i64) {
    let posts = post_all()
    ctx_html(ctx, 200, posts_index_page(ctx, posts))
}
```

---

## 5. Reading query results in views

`forge_result_col` retrieves a column value from a query result by row index and column name.

```jda
let posts = post_all()
loop r in 0..posts.count {
    let id     = forge_result_col(posts, r, "id")
    let title  = forge_result_col(posts, r, "title")
    let author = forge_result_col(posts, r, "author")
    // build HTML using id, title, author
}
```

All values returned by `forge_result_col` are `[]i8` strings. Escape them with `forge_h` before embedding in HTML.

---

## 6. Partials

Partials are named, reusable view fragments. Register a function as a partial once at startup; render it by name from any view.

### Defining a partial

A partial function receives a `vars` pointer (a key/value store) and returns `[]i8`.

```jda
fn render_post_row(vars: &i64) -> []i8 {
    let title = forge_partial_var(vars, "title")
    let id    = forge_partial_var(vars, "id")
    ret "<tr><td>" + forge_h(title) + "</td><td>" +
        forge_link_to("View", "/posts/" + id) + "</td></tr>"
}
```

### Registering a partial

```jda
forge_partial_register("post_row", fn_addr(render_post_row))
```

Call `forge_partial_register` once at application startup before any request is handled.

### Rendering a partial

```jda
let vars = forge_partial_vars_new()
forge_partial_var_set(vars, "title", post_title)
forge_partial_var_set(vars, "id",    post_id)
let html = forge_partial("post_row", vars)
```

Variables are string key/value pairs. Retrieve them inside the partial with `forge_partial_var`.

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
