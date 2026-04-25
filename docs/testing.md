# Testing

JDA Forge includes an in-memory test driver. Tests fire real HTTP requests through the router without opening a socket — the same handler code runs, the same middleware executes, and the real database is hit (a test database, not your development one).

Set `FORGE_ENV=test` and write plain functions whose names start with `test_`.

---

## The one-liner pattern

Each test is typically a single line: a request paired with a chained assertion.

```jda
forge_get(posts_path).ok(200)
forge_get(posts_path).ok(200).has("Blog Posts")
forge_post(posts_path, body).redirect()
forge_delete(post_path("1")).redirect()
forge_get(post_path("99999")).ok(404)
```

`forge_get`, `forge_post`, `forge_put`, and `forge_delete` send a request and return a response. Assertion methods chain off the response via UFCS:

| Method | What it asserts |
|---|---|
| `.ok(code)` | Status matches `code` exactly |
| `.redirect()` | Any 3xx status |
| `.has(s)` | Body contains substring `s` |
| `.not_has(s)` | Body does not contain substring `s` |

All assertion methods return the response so you can chain:

```jda
forge_get("/api/users").ok(200).has("\"email\"").not_has("\"password\"")
```

POST and PUT automatically attach a valid CSRF token.

---

## Path helpers

Scaffold generates path constants and helpers for each resource. Use them instead of hard-coded strings:

```jda
// Constants — no call needed
forge_get(posts_path)        // GET /posts
forge_get(new_post_path)     // GET /posts/new

// Functions — pass the id
forge_get(post_path("1"))         // GET /posts/1
forge_get(edit_post_path("1"))    // GET /posts/1/edit
forge_delete(post_path("1"))      // DELETE /posts/1
```

The helpers are defined at the top of each routes file and are in scope for the whole build.

---

## Sending a body

Pass form-encoded or JSON strings as the second argument to `forge_post` / `forge_put`:

```jda
// Form data
forge_post(posts_path, "title=Hello&body=Long+enough+body&author=Alice").redirect()

// JSON — Content-Type: application/json is set automatically when body starts with { or [
forge_post("/api/users", "{\"email\":\"test@example.com\"}").ok(201)
```

---

## Reading the response

When you need to inspect beyond assertions:

```jda
let res    = forge_get(posts_path)
let body   = res.body    // []i8
let status = res.status  // i32
```

---

## Test environment behaviour

When `FORGE_ENV=test`:

- **SMTP is disabled.** Emails are captured in memory and never sent.
- **Database** uses `DATABASE_URL` from `.env.test`. Point it at a dedicated test database.
- **Sessions** work normally — the session store is active and cookies are tracked across the in-memory request chain.
- **CSRF tokens** are automatically included by `forge_post`, `forge_put`, and `forge_delete`.

---

## Running tests

```bash
forge test
# Runs: FORGE_ENV=test ./test_runner

# Or run a single test file directly
FORGE_ENV=test jda run test/test_blog.jda
```

The `test_runner` binary is built by `forge test` and discovers all functions named `test_*` in the files under `test/`. Each test function runs in order; the runner reports pass/fail and exits non-zero if any assertion fails.

---

## Test file structure

```jda
// test/test_posts.jda

fn test_posts_index() {
    forge_get(posts_path).ok(200).has("Posts")
}

fn test_post_create_valid() {
    let body = "title=Hello&body=Long+enough+body&author=Alice"
    forge_post(posts_path, body).redirect()
}

fn test_post_create_missing_title() {
    forge_post(posts_path, "title=&body=Some+body&author=Alice").redirect()
}

fn test_post_not_found() {
    forge_get(post_path("99999")).ok(404)
}

fn test_post_delete() {
    forge_delete(post_path("1")).redirect()
}
```

One file per resource. No required structure beyond `test/` and `test_*` function names.

---

## Database in tests

Tests hit a real database. Control its state with a `test_setup` function called at the top of each test that depends on data:

```jda
fn test_setup() {
    forge_exec_sql("DELETE FROM posts")
    forge_exec_sql("INSERT INTO posts (title, body, author) VALUES ('Test', 'Body text here', 'Alice')")
}

fn test_posts_index() {
    test_setup()
    forge_get(posts_path).ok(200).has("Test")
}
```

`forge_exec_sql` runs arbitrary SQL against the test database. Keep `.env.test` checked in (it contains no real secrets).

---

## Generated test files

`forge generate scaffold Post title:string` creates `test/test_posts.jda` with skeleton tests:

```jda
fn test_posts_index() {
    forge_get(posts_path).ok(200)
}

fn test_post_not_found() {
    forge_get(post_path("99999")).ok(404)
}
```

Fill in create, update, delete, and validation cases to match your handler logic.

---

## Quick reference

**Request functions:**

| Function | What it does |
|---|---|
| `forge_get(path)` | GET request |
| `forge_post(path, body)` | POST with body, CSRF included |
| `forge_put(path, body)` | PUT with body, CSRF included |
| `forge_delete(path)` | DELETE, CSRF included |

**Chainable assertion methods** (UFCS on the response):

| Method | What it asserts |
|---|---|
| `.ok(code)` | Exact status code match |
| `.redirect()` | Any 3xx status |
| `.has(s)` | Body contains string |
| `.not_has(s)` | Body does not contain string |

**Low-level helpers** (when you need to inspect manually):

| Function | Returns |
|---|---|
| `forge_assert_status(res, code)` | Assert and return bool |
| `forge_assert_redirect(res)` | Assert and return bool |
| `forge_assert_body_has(res, s)` | Assert and return bool |
| `forge_exec_sql(query)` | Run SQL against test database |

**Path helpers** (generated per resource, e.g. for `Post`):

| Helper | Returns |
|---|---|
| `posts_path` | `/posts` |
| `new_post_path` | `/posts/new` |
| `post_path(id)` | `/posts/<id>` |
| `edit_post_path(id)` | `/posts/<id>/edit` |

Run tests: `forge test` or `FORGE_ENV=test jda run test/test_posts.jda`
