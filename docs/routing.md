# Routing and Request/Response Reference

This document covers everything you need to handle HTTP in JDA Forge: registering routes, reading request data, sending responses, middleware, WebSockets, Server-Sent Events, and static files.

---

## Table of Contents

1. [Application setup](#1-application-setup)
2. [Route registration](#2-route-registration)
3. [Reading request data](#3-reading-request-data)
4. [Sending responses](#4-sending-responses)
5. [Cookies](#5-cookies)
6. [Flash messages](#6-flash-messages)
7. [Sessions](#7-sessions)
8. [Middleware](#8-middleware)
9. [WebSocket](#9-websocket)
10. [Server-Sent Events (SSE)](#10-server-sent-events-sse)
11. [Static files](#11-static-files)
12. [Generating routes with scaffold](#12-generating-routes-with-scaffold)

---

## 1. Application setup

Every Forge application starts with a call to `app_new` or `app_new_config`, followed by route registration and a blocking call to `app_listen`.

```jda
fn main() {
    let app = app_new()

    app_get(app, "/", fn_addr(handle_root))

    app_listen(app, 8080)
}
```

To pass a `ForgeConfig` (database URL, secret key, log level, etc.) use `app_new_config`:

```jda
fn main() {
    load_env()
    let cfg = app_config()
    let app = app_new_config(cfg)

    // register routes ...

    app_listen(app, 8080)
}
```

`app_listen` blocks forever, serving requests on the given port. It does not return under normal operation.

---

## 2. Route registration

### 2.1 HTTP method helpers

```jda
app_get   (app, "/path", fn_addr(handler))
app_post  (app, "/path", fn_addr(handler))
app_put   (app, "/path", fn_addr(handler))
app_patch (app, "/path", fn_addr(handler))
app_delete(app, "/path", fn_addr(handler))
```

Each function takes the application handle, a path string, and a function pointer obtained with `fn_addr`. The handler signature is always:

```jda
fn handler_name(ctx: i64)
```

`ctx` is an opaque integer handle — pass it unchanged to every `ctx_*` function.

### 2.2 Static paths

```jda
app_get(app, "/",          fn_addr(handle_root))
app_get(app, "/about",     fn_addr(handle_about))
app_post(app, "/login",    fn_addr(handle_login))
app_delete(app, "/logout", fn_addr(handle_logout))
```

### 2.3 Named parameters

Prefix a path segment with `:` to capture it as a named parameter. Retrieve the captured value inside the handler with `ctx_param`.

```jda
app_get(app, "/users/:id",       fn_addr(handle_user_show))
app_get(app, "/posts/:id/edit",  fn_addr(handle_post_edit))
app_put(app, "/posts/:id",       fn_addr(handle_post_update))
```

```jda
fn handle_user_show(ctx: i64) {
    let id = ctx_param(ctx, "id")
    // id holds the string that matched :id
}
```

Multiple named parameters in a single path are independent:

```jda
app_delete(app, "/posts/:post_id/comments/:id", fn_addr(handle_comment_delete))

fn handle_comment_delete(ctx: i64) {
    let post_id = ctx_param(ctx, "post_id")
    let id      = ctx_param(ctx, "id")
}
```

### 2.4 Wildcard parameters

Use `*name` as the final path segment to capture everything that follows:

```jda
app_get(app, "/files/*path", fn_addr(handle_files))

fn handle_files(ctx: i64) {
    let path = ctx_param(ctx, "path")
    // GET /files/docs/api/intro.html  =>  path = "docs/api/intro.html"
}
```

A wildcard matches across `/` boundaries and must appear at the end of the pattern.

### 2.5 The routes DSL

Forge uses a two-file convention to achieve Rails-like routing. Scaffold generates both files automatically.

**`config/routes`** — the DSL file you edit (never the generated `.jda`):

```
root "posts#index"

resources "posts" do
  resources "comments"
end

namespace "admin" do
  resources "users"
end

scope "/api/v2" do
  get "/status" "api#status" as "api_v2_status"
end

get "/login"  "sessions#new"    as "login"
post "/login" "sessions#create"
delete "/logout" "sessions#delete" as "logout"
```

Run `forge build` (or `forge server`, `forge test`) — Forge compiles `config/routes` into `config/routes.jda` automatically before calling make. The generated file contains path helpers and the `routes()` function. **Do not edit `config/routes.jda` directly.**

**`config/controllers.jda`** — registers every controller action once, using `fn_addr`:

```jda
fn forge_controllers_init() {
    forge_action_register("posts", "index",  fn_addr(posts_index))
    forge_action_register("posts", "new",    fn_addr(posts_new))
    forge_action_register("posts", "create", fn_addr(posts_create))
    forge_action_register("posts", "show",   fn_addr(posts_show))
    forge_action_register("posts", "edit",   fn_addr(posts_edit))
    forge_action_register("posts", "update", fn_addr(posts_update))
    forge_action_register("posts", "delete", fn_addr(posts_delete))

    forge_action_register("comments", "create", fn_addr(comments_create))
    forge_action_register("comments", "delete", fn_addr(comments_delete))
}
```

`main.jda` calls `forge_controllers_init()` once before `routes(app)`. Scaffold appends to this file automatically.

`app.resources("posts")` looks up `posts_index`, `posts_new`, … `posts_delete` from the registry. If an action is not registered (e.g. `comments` only has `create` and `delete`), that route is simply skipped.

### 2.6 `app.resources` — 7 RESTful routes

```jda
app.resources("posts")
```

Routes registered:

| Method | Path |
|---|---|
| GET | `/posts` |
| GET | `/posts/new` |
| POST | `/posts` |
| GET | `/posts/:id` |
| GET | `/posts/:id/edit` |
| PUT | `/posts/:id` |
| DELETE | `/posts/:id` |

Returns a `&ForgeScope` prefixed at `/posts/:post_id` for nesting.

### 2.7 Nested resources

Chain `.resources()` off the returned scope:

```jda
app.resources("posts").resources("comments")
```

Three levels deep:

```jda
app.resources("users").resources("posts").resources("comments")
```

Registered paths: `/users`, `/users/:user_id/posts`, `/users/:user_id/posts/:post_id/comments/…`

### 2.8 Singular resource — `app.resource`

For resources with no index and no `:id` (profile, settings, cart):

```jda
app.resource("profile")
```

Routes registered: `GET /profile/new`, `POST /profile`, `GET /profile`, `GET /profile/edit`, `PUT /profile`, `DELETE /profile`.

### 2.9 Namespace — `app.namespace`

```jda
let admin = app.namespace("admin")
admin.resources("users")
admin.resources("posts")
```

Registered paths: `/admin/users`, `/admin/users/:user_id`, `/admin/posts`, etc.

### 2.10 Custom routes — `app.get / app.post / app.put / app.delete`

```jda
app.get("/login",  "sessions#new")
app.post("/login", "sessions#create")
app.delete("/logout", "sessions#delete")
```

These use the registry to look up the handler — same `"controller#action"` string as Rails.

### 2.11 Concerns

A concern is a plain function that takes a `&ForgeScope`. Apply it to multiple parent scopes:

```jda
fn concern_commentable(s: &ForgeScope) {
    s.resources("comments")
}

fn routes(app: &ForgeApp) {
    concern_commentable(app.resources("posts"))
    concern_commentable(app.resources("articles"))
}
```

### 2.12 Explicit `fn_addr` form (power users)

When you need precise control — partial action sets, non-conventional handlers — use the explicit variants directly:

```jda
forge_resources_explicit(app, "posts",
    fn_addr(posts_index), fn_addr(posts_new),    fn_addr(posts_create),
    fn_addr(posts_show),  fn_addr(posts_edit),   fn_addr(posts_update),
    fn_addr(posts_delete))

forge_scope_resources_explicit(posts_scope, "comments",
    0, 0, fn_addr(comments_create),
    0, 0, 0, fn_addr(comments_delete))
```

Pass `0` for any handler to skip that route.

### 2.6 Route matching rules

- Routes are matched in registration order. The first match wins.
- Static segments take priority over named parameters: `/posts/new` registered before `/posts/:id` will match the literal `new` path before the parameter handler does.
- Wildcard routes match last among otherwise equivalent prefixes.

---

## 3. Reading request data

All request-reading functions accept `ctx` and a string key. They return `[]i8` (a string slice). An empty slice (`len == 0`) means the value was absent.

### 3.1 URL parameters

```jda
let id = ctx_param(ctx, "id")
```

Returns the value captured by a `:id` segment. Returns an empty string if the route has no such parameter.

### 3.2 Query string

```jda
// GET /articles?page=3&per_page=20
let page     = ctx_query(ctx, "page")      // "3"
let per_page = ctx_query(ctx, "per_page")  // "20"
let missing  = ctx_query(ctx, "q")         // "" (len == 0)
```

### 3.3 Form data

```jda
// POST /login  (Content-Type: application/x-www-form-urlencoded)
let email    = ctx_form(ctx, "email")
let password = ctx_form(ctx, "password")
```

`ctx_form` parses an `application/x-www-form-urlencoded` body. For multipart form data, see `ctx_body`.

### 3.4 Request headers

```jda
let auth   = ctx_header(ctx, "Authorization")
let ct     = ctx_header(ctx, "Content-Type")
let tenant = ctx_header(ctx, "X-Tenant-Id")
```

Header names are case-insensitive.

### 3.5 Raw body

```jda
let raw = ctx_body(ctx)   // []i8
```

Use this to read JSON bodies, binary uploads, or any content type that is not URL-encoded form data.

Example — parse a JSON API request:

```jda
fn handle_api_create(ctx: i64) {
    let raw = ctx_body(ctx)
    if raw.len == 0 {
        ctx_bad_request(ctx, "empty body")
        ret
    }
    // pass raw to a JSON parsing function
    let title = json_get(raw, "title")
    // ...
}
```

### 3.6 Request metadata

```jda
let method = ctx_method(ctx)   // "GET", "POST", "DELETE", etc.
let path   = ctx_path(ctx)     // "/posts/42"
let ip     = ctx_ip(ctx)       // "203.0.113.5"
```

### 3.7 Shared context values

Middleware and handlers can pass arbitrary key/value strings through the request context:

```jda
ctx_set(ctx, "key", "value")
let val = ctx_get(ctx, "key")
```

The built-in `forge_request_id` middleware, for example, stores the request ID:

```jda
let rid = ctx_get(ctx, "request_id")
```

---

## 4. Sending responses

Every handler must send exactly one response. Calling a response function does not automatically stop execution — use `ret` after it.

### 4.1 HTML

```jda
ctx_html(ctx, 200, "<h1>Hello</h1>")
```

Sets `Content-Type: text/html; charset=utf-8`.

### 4.2 JSON

```jda
ctx_json(ctx, 200, "{\"id\": 1, \"title\": \"Hello\"}")
```

Sets `Content-Type: application/json`.

### 4.3 Plain text

```jda
ctx_text(ctx, 200, "pong")
```

Sets `Content-Type: text/plain; charset=utf-8`.

### 4.4 Redirects

```jda
ctx_redirect(ctx, "/posts")           // 302 Found
ctx_redirect_perm(ctx, "/new/path")   // 301 Moved Permanently
```

### 4.5 Status helpers

Each helper sends an empty body (or a short error message) with the appropriate status code.

| Function | Status | Notes |
|---|---|---|
| `ctx_not_found(ctx)` | 404 | |
| `ctx_forbidden(ctx)` | 403 | |
| `ctx_unauthorized(ctx)` | 401 | |
| `ctx_bad_request(ctx, msg)` | 400 | `msg` is included in the response body |
| `ctx_unprocessable(ctx, json)` | 422 | `json` should be a JSON error object string |
| `ctx_too_many_requests(ctx)` | 429 | |

```jda
fn handle_api_show(ctx: i64) {
    let id = ctx_param(ctx, "id")
    let row = post_find(id)
    if row == 0 {
        ctx_not_found(ctx)
        ret
    }
    ctx_json(ctx, 200, post_to_json(row))
}
```

### 4.6 Custom response headers

Set arbitrary response headers before calling a response function:

```jda
ctx_set_header(ctx, "X-My-Header", "value")
ctx_set_header(ctx, "Cache-Control", "no-store")
ctx_json(ctx, 200, payload)
```

### 4.7 A complete CRUD example

```jda
```jda
// app/controllers/posts_controller.jda

fn posts_index(ctx: i64) {
    ctx_render(ctx, view_posts_index(ctx, post_published()))
}

fn posts_new(ctx: i64) {
    ctx_render(ctx, view_posts_new(ctx))
}

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

fn posts_show(ctx: i64) {
    let id   = ctx_param(ctx, "id")
    let post = post_find(id)
    if post.count == 0 { ctx_not_found(ctx)  ret }
    ctx_render(ctx, view_posts_show(ctx, post))
}

fn posts_edit(ctx: i64) {
    let id   = ctx_param(ctx, "id")
    let post = post_find(id)
    if post.count == 0 { ctx_not_found(ctx)  ret }
    ctx_render(ctx, view_posts_edit(ctx, post))
}

fn posts_update(ctx: i64) {
    let id    = ctx_param(ctx, "id")
    let title = ctx_form(ctx, "title")
    let body  = ctx_form(ctx, "body")

    let errs = post_validate(title, body, "placeholder")
    if forge_errors_any(errs) {
        ctx_flash_set(ctx, "alert", forge_errors_json(errs))
        ctx_redirect(ctx, edit_post_path(id))
        ret
    }

    if !post_update(id, title, body) {
        ctx_flash_set(ctx, "alert", "Could not update post.")
        ctx_redirect(ctx, edit_post_path(id))
        ret
    }

    ctx_flash_set(ctx, "notice", "Post updated.")
    ctx_redirect(ctx, post_path(id))
}

fn posts_delete(ctx: i64) {
    post_delete(ctx_param(ctx, "id"))
    ctx_flash_set(ctx, "notice", "Post deleted.")
    ctx_redirect(ctx, posts_path)
}
```

Pattern: validate → flash + redirect on failure → flash + redirect on success. Controllers use path helper constants and functions, never hard-coded strings.

---

## 5. Cookies

```jda
// Set a cookie: name, value, max-age in seconds
ctx_set_cookie(ctx, "theme", "dark", 2592000)   // 30 days

// Read a cookie
let theme = ctx_get_cookie(ctx, "theme")
if theme.len == 0 { theme = "light" }
```

`ctx_set_cookie` adds a `Set-Cookie` header to the response. Call it before the response function.

```jda
fn handle_preferences_save(ctx: i64) {
    let theme = ctx_form(ctx, "theme")
    ctx_set_cookie(ctx, "theme", theme, 31536000)   // 1 year
    ctx_redirect(ctx, "/preferences")
}
```

Cookie values are plain strings. For tamper-proof values (e.g., a user ID that must not be forged), use sessions instead.

---

## 6. Flash messages

Flash messages survive exactly one redirect. They are stored in the session, read on the next request, and then deleted. The session middleware must be present in the stack.

```jda
// Set a flash before redirecting
ctx_flash_set(ctx, "notice", "Your changes were saved.")
ctx_flash_set(ctx, "alert",  "Something went wrong.")
ctx_redirect(ctx, "/dashboard")

// Read the flash in the next request's handler (or in the layout template)
let notice = ctx_flash_get(ctx, "notice")
let alert  = ctx_flash_get(ctx, "alert")
```

Conventions used throughout Forge examples:

| Key | Meaning |
|---|---|
| `notice` | Success or informational message |
| `alert` | Error or warning |

Typical layout usage:

```jda
fn layout(body: []i8, ctx: i64) -> []i8 {
    let notice = ctx_flash_get(ctx, "notice")
    let alert  = ctx_flash_get(ctx, "alert")
    // include notice and alert in the rendered HTML
    ret "<html>..." + notice_html(notice) + alert_html(alert) + body + "</html>"
}
```

---

## 7. Sessions

Sessions require the `forge_session_start` middleware. Add it to the stack before any handler that needs session data.

```jda
app_use(app, fn_addr(forge_session_start))
```

Session data is stored server-side (in memory or a backing store depending on configuration) and keyed by a cookie sent to the browser.

```jda
// Store a value
ctx_session_set(ctx, "user_id", "42")

// Read a value
let user_id = ctx_session_get(ctx, "user_id")
if user_id.len == 0 {
    ctx_redirect(ctx, "/login")
    ret
}

// Remove one key
ctx_session_delete(ctx, "user_id")

// Destroy the entire session (logout)
ctx_session_clear(ctx)
ctx_redirect(ctx, "/login")
```

### Authentication pattern

```jda
fn handle_login_create(ctx: i64) {
    let email    = ctx_form(ctx, "email")
    let password = ctx_form(ctx, "password")

    let user_id = user_authenticate(email, password)
    if user_id.len == 0 {
        ctx_flash_set(ctx, "alert", "Invalid email or password.")
        ctx_redirect(ctx, "/login")
        ret
    }

    ctx_session_set(ctx, "user_id", user_id)
    ctx_flash_set(ctx, "notice", "Welcome back.")
    ctx_redirect(ctx, "/dashboard")
}

fn handle_logout(ctx: i64) {
    ctx_session_clear(ctx)
    ctx_redirect(ctx, "/login")
}
```

```jda
fn require_login(ctx: i64) {
    let uid = ctx_session_get(ctx, "user_id")
    if uid.len == 0 {
        ctx_redirect(ctx, "/login")
        ret
    }
    ctx_set(ctx, "current_user_id", uid)
}
```

Register `require_login` as middleware (globally or only for protected routes) before protected handlers run.

---

## 8. Middleware

Middleware functions run for every request, in registration order, before the matched route handler.

### 8.1 Registering middleware

```jda
app_use(app, fn_addr(my_middleware))
```

`app_use` must be called before `app_listen`. Middleware runs in the order it was registered.

### 8.2 Built-in middleware

| Function | Effect |
|---|---|
| `forge_logger` | Logs method, path, status, and duration for every request |
| `forge_request_id` | Adds `X-Request-Id` to every response; stores value in `ctx` under `"request_id"` |
| `forge_secure_headers` | Sets HSTS, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, and a default CSP |
| `forge_session_start` | Initialises the session cookie; required for flash messages and CSRF protection |
| `forge_csrf` | Blocks state-changing requests (POST, PUT, PATCH, DELETE) without a valid CSRF token; must come after `forge_session_start` |
| `forge_rate_limit` | Returns 429 after 100 requests per minute from the same IP |
| `forge_cors` | Adds permissive CORS headers; suitable for development; configure explicitly for production |
| `forge_jwt_auth` | Validates a `Bearer` token from the `Authorization` header |
| `forge_basic_auth` | Validates HTTP Basic credentials |
| `forge_compress` | Compresses responses with gzip when the client sends `Accept-Encoding: gzip` |

### 8.3 Recommended stack order

```jda
app_use(app, fn_addr(forge_logger))          // always first — logs everything
app_use(app, fn_addr(forge_request_id))      // before logger output if you log request IDs
app_use(app, fn_addr(forge_secure_headers))  // early — sets security headers unconditionally
app_use(app, fn_addr(forge_session_start))   // before CSRF and flash
app_use(app, fn_addr(forge_csrf))            // after session
app_use(app, fn_addr(forge_rate_limit))      // after request ID so limits are attributable
```

Order matters:

- `forge_session_start` must come before `forge_csrf` — the CSRF middleware reads the token from the session.
- `forge_logger` should come before anything that might short-circuit the request (e.g., auth or rate-limit middleware) so that rejected requests are still logged.
- Authentication middleware (`forge_jwt_auth`, `forge_basic_auth`) should come late enough that `forge_logger` and `forge_secure_headers` have already run.

### 8.4 Writing custom middleware

A middleware function has the same signature as a handler. Forge calls it automatically before the route handler; there is no explicit `next()` call.

```jda
fn my_middleware(ctx: i64) {
    // Code here runs before the handler.
    // Read from the request, set ctx values, or short-circuit with a response.
}
```

To short-circuit (stop the chain), send a response and return:

```jda
fn require_api_key(ctx: i64) {
    let key = ctx_header(ctx, "X-Api-Key")
    if key.len == 0 {
        ctx_unauthorized(ctx)
        ret
    }
    if !api_key_valid(key) {
        ctx_forbidden(ctx)
        ret
    }
    // No response sent — Forge continues to the next middleware / handler.
}
```

To pass data to the handler, use `ctx_set`:

```jda
fn tenant_middleware(ctx: i64) {
    let tenant = ctx_header(ctx, "X-Tenant-Id")
    if tenant.len == 0 {
        ctx_bad_request(ctx, "missing X-Tenant-Id header")
        ret
    }
    ctx_set(ctx, "tenant", tenant)
}

fn handle_data(ctx: i64) {
    let tenant = ctx_get(ctx, "tenant")
    // use tenant ...
}
```

### 8.5 Example: logging with request ID

```jda
fn audit_log(ctx: i64) {
    let rid    = ctx_get(ctx, "request_id")
    let method = ctx_method(ctx)
    let path   = ctx_path(ctx)
    let ip     = ctx_ip(ctx)
    // write to your audit log
    audit_write(rid, method, path, ip)
}

// in main:
app_use(app, fn_addr(forge_logger))
app_use(app, fn_addr(forge_request_id))
app_use(app, fn_addr(audit_log))         // request_id is already set
```

---

## 9. WebSocket

Upgrade an HTTP GET request to a WebSocket connection with `forge_ws_upgrade`. The function returns a connection handle on success (`>= 0`) or a negative value on failure.

```jda
fn handle_ws(ctx: i64) {
    let conn = forge_ws_upgrade(ctx)
    if conn < 0 { ret }

    loop {
        let msg = forge_ws_read(conn)
        if msg.len == 0 {
            forge_ws_close(conn)
            ret
        }
        forge_ws_write(conn, "echo: " + msg)
    }
}

app_get(app, "/ws", fn_addr(handle_ws))
```

| Function | Description |
|---|---|
| `forge_ws_upgrade(ctx)` | Performs the HTTP upgrade handshake; returns connection handle |
| `forge_ws_read(conn)` | Blocks until a frame arrives; returns `[]i8` with the message text; returns empty slice on close or error |
| `forge_ws_write(conn, msg)` | Sends a text frame |
| `forge_ws_close(conn)` | Closes the connection |

`forge_ws_read` returns an empty slice (`len == 0`) when the client closes the connection or a network error occurs. Always check and close before returning.

### Chat broadcast example

```jda
fn handle_chat(ctx: i64) {
    let conn = forge_ws_upgrade(ctx)
    if conn < 0 { ret }

    ws_pool_add(conn)

    loop {
        let msg = forge_ws_read(conn)
        if msg.len == 0 {
            ws_pool_remove(conn)
            forge_ws_close(conn)
            ret
        }
        ws_pool_broadcast(msg)
    }
}
```

---

## 10. Server-Sent Events (SSE)

SSE lets a server push a stream of text events to the browser over a single long-lived HTTP connection.

```jda
fn handle_sse(ctx: i64) {
    forge_sse_start(ctx)

    let i = 0
    loop {
        forge_sse_send(ctx, "update", i64_to_str(i))
        i = i + 1
        forge_sleep_ms(1000)
    }
}

app_get(app, "/events", fn_addr(handle_sse))
```

| Function | Description |
|---|---|
| `forge_sse_start(ctx)` | Sends the SSE headers (`Content-Type: text/event-stream`, `Cache-Control: no-cache`) and flushes |
| `forge_sse_send(ctx, event, data)` | Sends one event with the given event name and data string |
| `forge_sleep_ms(ms)` | Sleeps for `ms` milliseconds (used to pace the stream) |

Each call to `forge_sse_send` writes:

```
event: update
data: 0

```

The browser's `EventSource` API receives these as named events. Clients reconnect automatically when the connection drops.

---

## 11. Static files

Serve a local directory under a URL prefix:

```jda
forge_static(app, "/static", "public/")
```

This registers a wildcard route internally. Any request whose path begins with `/static` maps to the `public/` directory:

```
GET /static/app.js          =>  public/app.js
GET /static/images/logo.png =>  public/images/logo.png
```

Call `forge_static` after middleware registration but before `app_listen`. Multiple static mounts are supported:

```jda
forge_static(app, "/static",  "public/")
forge_static(app, "/uploads", "storage/uploads/")
```

Forge sets `Content-Type` based on the file extension and serves `Last-Modified` and `ETag` headers for conditional GET support. Missing files return 404.

---

## 12. Generating routes with scaffold

The scaffold generator creates a complete vertical slice — migration, model, controller, views, and tests — from a single command:

```bash
forge generate scaffold Post title:string body:string author:string
```

This creates:

```
db/migrate/001_create_posts.sql
app/models/post.jda
app/controllers/posts_controller.jda
app/views/posts/index.html.jda
app/views/posts/show.html.jda
app/views/posts/new.html.jda
app/views/posts/edit.html.jda
test/test_posts.jda
```

It also appends `resources "posts"` to `config/routes` and registers all actions in `config/controllers.jda` automatically. No manual wiring required.

Generated controller actions for a `Post` resource:

| Action | Method | Path |
|---|---|---|
| `posts_index` | GET | `/posts` |
| `posts_new` | GET | `/posts/new` |
| `posts_create` | POST | `/posts` |
| `posts_show` | GET | `/posts/:id` |
| `posts_edit` | GET | `/posts/:id/edit` |
| `posts_update` | PUT | `/posts/:id` |
| `posts_delete` | DELETE | `/posts/:id` |

### Path helpers

`forge build` generates path helpers in `config/routes.jda` from your `config/routes` DSL:

```jda
// Zero-arg paths — constants, no call needed
let posts_path: []i8    = "/posts"
let new_post_path: []i8 = "/posts/new"

// Id-taking paths — functions
fn post_path(id: []i8) -> []i8      { ret forge_path_id("posts", id) }
fn edit_post_path(id: []i8) -> []i8 { ret forge_path_edit("posts", id) }
```

Use them in controllers, views, and tests — never hard-code path strings:

```jda
// In a controller
ctx_redirect(ctx, posts_path)
ctx_redirect(ctx, post_path(id))

// In a test
forge_get(posts_path).ok(200)
forge_delete(post_path("1")).redirect()
```

For nested resources, define a one-line helper using `forge_nested_path*`:

```jda
fn post_comments_path(post_id: []i8) -> []i8      { ret forge_nested_path("posts", post_id, "comments") }
fn post_comment_path(post_id: []i8, id: []i8) -> []i8 { ret forge_nested_path_id("posts", post_id, "comments", id) }
```

All `forge_path*` and `forge_nested_path*` functions:

| Function | Result |
|---|---|
| `forge_path("posts")` | `/posts` |
| `forge_path_new("posts")` | `/posts/new` |
| `forge_path_id("posts", id)` | `/posts/<id>` |
| `forge_path_edit("posts", id)` | `/posts/<id>/edit` |
| `forge_nested_path(par, pid, child)` | `/par/pid/child` |
| `forge_nested_path_new(par, pid, child)` | `/par/pid/child/new` |
| `forge_nested_path_id(par, pid, child, id)` | `/par/pid/child/id` |
| `forge_nested_path_edit(par, pid, child, id)` | `/par/pid/child/id/edit` |

### Naming conventions — enforced by scaffold

Scaffold enforces these conventions and raises an error if they are violated:

| Layer | File | Function prefix |
|---|---|---|
| Controller | `app/controllers/posts_controller.jda` | `posts_` |
| Model | `app/models/post.jda` | `post_` |
| View | `app/views/posts/index.html.jda` | `view_posts_` |

Resource names must be PascalCase: `forge generate scaffold Post` ✓ — `forge generate scaffold post` is an error.

---

## 13. Scopes — raw prefix groups

`forge_scope` wraps an app with a path prefix. Use it when `forge_resources` / `forge_namespace` are not the right fit — arbitrary prefix, non-standard method mix, or adding extra routes alongside a resource.

```jda
let api = forge_scope(app, "/api/v2")
api.get("/status",        fn_addr(api_status))
api.get("/users/:id",     fn_addr(api_user_show))
api.post("/users",        fn_addr(api_user_create))
```

### Deeply nested scopes with `forge_scope_nested`

Build scopes from existing scopes for multi-level nesting:

```jda
fn routes(app: &ForgeApp) {
    let users    = forge_scope(app, "/users/:user_id")
    let posts    = forge_scope_nested(users,  "/posts/:post_id")
    let comments = forge_scope_nested(posts,  "/comments/:comment_id")

    users.get("/posts",        fn_addr(user_posts_index))
    users.post("/posts",       fn_addr(user_posts_create))

    posts.get("/comments",     fn_addr(post_comments_index))
    posts.post("/comments",    fn_addr(post_comments_create))

    comments.post("/likes",        fn_addr(comment_likes_create))
    comments.delete("/likes/:id",  fn_addr(comment_likes_delete))
}
```

Registered paths: `GET /users/:user_id/posts`, `POST /users/:user_id/posts/:post_id/comments`, `DELETE /users/:user_id/posts/:post_id/comments/:comment_id/likes/:id`, etc.

### Path helpers for namespaced and nested routes

```jda
// Namespaced — flat constants and forge_path_id
let admin_posts_path: []i8 = "/admin/posts"
fn admin_post_path(id: []i8) -> []i8 { ret forge_path_id("admin/posts", id) }

// Nested — one-liners using forge_nested_path*
fn post_comments_path(post_id: []i8) -> []i8 {
    ret forge_nested_path("posts", post_id, "comments")
}
fn post_comment_path(post_id: []i8, id: []i8) -> []i8 {
    ret forge_nested_path_id("posts", post_id, "comments", id)
}
fn new_post_comment_path(post_id: []i8) -> []i8 {
    ret forge_nested_path_new("posts", post_id, "comments")
}
fn edit_post_comment_path(post_id: []i8, id: []i8) -> []i8 {
    ret forge_nested_path_edit("posts", post_id, "comments", id)
}
```

### Scope method reference

| Function | What it does |
|---|---|
| `forge_scope(app, "/prefix")` | Scope at arbitrary prefix |
| `forge_scope_nested(scope, "/suffix")` | Child scope — concatenates prefix + suffix |
| `forge_namespace(app, "admin")` | Scope at `/admin` (Rails namespace alias) |
| `forge_resources(app, "posts", ...)` | 7 routes + returns `&ForgeScope` at `/posts/:post_id` |
| `forge_scope_resources(scope, "comments", ...)` | 7 nested routes + returns deeper `&ForgeScope` |
| `forge_resource(app, "profile", ...)` | 6 singular routes (no index, no :id) |
| `forge_scope_resource(scope, "profile", ...)` | Singular resource within a scope |

---

## 14. Passing a model object to a path helper

`post_path` takes a `[]i8` id. When you have a `&ForgeResult` from a query, use `.id()` via UFCS to extract the id column value:

```jda
let post = post_find(id)
let url  = post_path(post.id())      // post.id() = forge_result_id(post) = forge_result_col(post, 0, "id")

ctx_redirect(ctx, post_path(post.id()))
```

`forge_result_id` is the underlying function; `.id()` is the UFCS shorthand. Works on any `&ForgeResult` — the column looked up is always `"id"`.

For tests, `post_path(post.id())` reads naturally with the chainable DSL:

```jda
fn test_post_show() {
    test_setup()
    let post = post_find("1")
    forge_get(post_path(post.id())).ok(200).has("Hello World")
}
```
