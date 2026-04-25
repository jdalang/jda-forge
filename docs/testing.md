# Testing

JDA Forge includes an in-memory test driver. Tests fire real HTTP requests through the router without opening a socket — the same handler code runs, the same middleware executes, and the real database is hit (a test database, not your development one).

Set `FORGE_ENV=test` and write plain functions whose names start with `test_`.

---

## Firing requests

Four functions cover the standard HTTP methods. Each returns a response handle you pass to assertion functions.

```jda
let res = forge_test_get   ("/posts")
let res = forge_test_post  ("/posts", "title=Hello&body=World&author=Alice")
let res = forge_test_put   ("/posts/1", "title=Updated")
let res = forge_test_delete("/posts/1")
```

- `forge_test_post`, `forge_test_put`, and `forge_test_delete` automatically attach a valid CSRF token, so you do not need to obtain or pass one in tests.
- The body string can be form-encoded (`key=value&key2=value2`) or a raw JSON string — pass whatever the handler expects.
- Path parameters, query strings, and everything else work exactly as they do in production.

---

## Assertions

### Status code

```jda
forge_assert_status(res, 200)    // exact match — fails if status differs
forge_assert_status(res, 404)
forge_assert_status(res, 201)
```

### Redirect

```jda
forge_assert_redirect(res)       // passes for any 3xx response
```

Use this when the exact target URL is not important, or when you only care that the handler redirected rather than rendering inline.

### Content-Type

```jda
forge_assert_json(res)           // Content-Type must be application/json
```

### Body content

```jda
forge_assert_contains    (res, "Hello")    // body contains substring
forge_assert_not_contains(res, "error")   // body does not contain substring
```

Both are case-sensitive. Pass a literal string or any `[]i8` slice.

---

## Reading the response

When you need to inspect the response directly rather than through assertions:

```jda
let body   = forge_test_res_body  (res)                    // []i8
let status = forge_test_res_status(res)                    // i64
let header = forge_test_res_header(res, "Content-Type")    // []i8
```

`forge_test_res_body` returns the full response body as a byte slice. Use `forge_assert_contains` for simple substring checks; read the body directly when you need to parse it or extract a value.

---

## Test environment behaviour

When `FORGE_ENV=test`:

- **SMTP is disabled.** Emails are captured in memory and never sent. Your handlers can call mail functions without side effects.
- **Database** uses `DATABASE_URL` from `.env.test`. This should point to a dedicated test database that you can freely wipe between runs.
- **Sessions** work normally — the session store is active and cookies are tracked across the in-memory request chain.
- **CSRF tokens** are automatically included by `forge_test_post`, `forge_test_put`, and `forge_test_delete`.

---

## Running tests

```bash
make test
# Runs: FORGE_ENV=test ./test_runner

# Or run a single test file directly
FORGE_ENV=test jda run test/test_blog.jda
```

The `test_runner` binary is built by `make` and discovers all functions named `test_*` in the files under `test/`. Each test function runs in order; the runner reports pass/fail and exits non-zero if any assertion fails.

---

## Test file structure

Test files live in `test/` and are named after the resource or feature they cover.

```jda
// test/test_posts.jda

fn test_posts_index() {
    let res = forge_test_get("/posts")
    forge_assert_status(res, 200)
}

fn test_post_create_valid() {
    let res = forge_test_post("/posts", "title=Hello&body=Long+enough+body&author=Alice")
    forge_assert_redirect(res)
}

fn test_post_create_missing_title() {
    let res = forge_test_post("/posts", "title=&body=Some+body&author=Alice")
    forge_assert_redirect(res)   // redirects to /posts/new with flash
}

fn test_post_not_found() {
    let res = forge_test_get("/posts/99999")
    forge_assert_status(res, 404)
}
```

One file per resource is a reasonable default. There is no required structure beyond placing files under `test/` and naming test functions `test_*`.

---

## Database in tests

Tests hit a real database. You are responsible for controlling its state. The standard approach is a `test_setup` function that truncates affected tables and inserts known seed rows, called at the top of each test that depends on data.

```jda
fn test_setup() {
    forge_exec_sql("DELETE FROM posts")
    forge_exec_sql("INSERT INTO posts (title, body, author) VALUES ('Test', 'Body text here', 'Alice')")
}

fn test_posts_index() {
    test_setup()
    let res = forge_test_get("/posts")
    forge_assert_status(res, 200)
    forge_assert_contains(res, "Test")
}
```

`forge_exec_sql` runs arbitrary SQL against the test database. Use it to seed rows, truncate tables, or check state after a mutation. For tests that create data through the HTTP layer (a `forge_test_post` to `/posts`), the row ends up in the test database — subsequent tests should not rely on that state unless they call `test_setup` first.

Keep `.env.test` checked in (it contains no real secrets) and document the command to create the test database in your project README or Makefile.

---

## Testing JSON APIs

For handlers that return JSON, combine `forge_assert_json` with `forge_assert_contains` to verify both the Content-Type and the shape of the response body.

```jda
fn test_api_users() {
    let res = forge_test_get("/api/users")
    forge_assert_status(res, 200)
    forge_assert_json(res)
    forge_assert_contains(res, "\"email\"")
}

fn test_api_create_user() {
    let res = forge_test_post("/api/users", "{\"email\":\"test@example.com\"}")
    forge_assert_status(res, 201)
}
```

When posting JSON, pass the raw JSON string as the body. The handler reads `ctx` as normal — the in-memory driver sets the correct `Content-Type: application/json` request header when the body string starts with `{` or `[`.

For detailed response inspection, read the body and check specific fields:

```jda
fn test_api_user_fields() {
    let res  = forge_test_get("/api/users/1")
    let body = forge_test_res_body(res)
    forge_assert_json(res)
    forge_assert_contains(res, "\"id\"")
    forge_assert_contains(res, "\"email\"")
    forge_assert_not_contains(res, "\"password\"")
}
```

---

## Generated test files

`forge generate scaffold Post title:string` creates `test/test_posts.jda` alongside the model, controller, and views. The generated file contains skeleton tests for the index and not-found cases:

```jda
fn test_posts_index() {
    let res = forge_test_get("/posts")
    forge_assert_status(res, 200)
}

fn test_post_not_found() {
    let res = forge_test_get("/posts/99999")
    forge_assert_status(res, 404)
}
```

Fill in the remaining cases (create, update, delete, validation errors) to match your handler logic.

---

## Quick reference

| Function | What it does |
|---|---|
| `forge_test_get(path)` | GET request to path |
| `forge_test_post(path, body)` | POST with body, CSRF included |
| `forge_test_put(path, body)` | PUT with body, CSRF included |
| `forge_test_delete(path)` | DELETE, CSRF included |
| `forge_assert_status(res, code)` | Exact status code match |
| `forge_assert_redirect(res)` | Any 3xx status |
| `forge_assert_json(res)` | Content-Type is application/json |
| `forge_assert_contains(res, s)` | Body contains string |
| `forge_assert_not_contains(res, s)` | Body does not contain string |
| `forge_test_res_body(res)` | Read body as `[]i8` |
| `forge_test_res_status(res)` | Read status as `i64` |
| `forge_test_res_header(res, name)` | Read response header as `[]i8` |
| `forge_exec_sql(query)` | Run SQL against test database |

Run tests: `make test` or `FORGE_ENV=test jda run test/test_posts.jda`
