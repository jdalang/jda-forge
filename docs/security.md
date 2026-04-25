# Security Guide

This guide covers every security concern a Forge developer needs to handle. It is organized by threat, explains what Forge handles automatically, what you must do yourself, and provides working code for every recommendation.

---

## Table of Contents

1. [SQL Injection](#sql-injection)
2. [Cross-Site Scripting (XSS)](#cross-site-scripting-xss)
3. [CSRF Protection](#csrf-protection)
4. [Authentication](#authentication)
5. [Secure HTTP Headers](#secure-http-headers)
6. [Rate Limiting](#rate-limiting)
7. [Password Hashing](#password-hashing)
8. [Secrets Management](#secrets-management)
9. [CORS](#cors)
10. [Signed Cookies](#signed-cookies)
11. [Security Checklist](#security-checklist)

---

## SQL Injection

SQL injection happens when unsanitized user input is interpolated directly into a SQL string, letting an attacker rewrite your query. It is the most critical class of web vulnerability and trivially achievable if you use raw string building.

### What Forge does automatically

All named query builder methods escape their value arguments before they reach the database. The following are safe to use with any user-supplied data:

| Method | Generated SQL |
|---|---|
| `where_eq(col, val)` | `col = 'escaped_val'` |
| `where(col, op, val)` | `col op 'escaped_val'` |
| `where_not(col, val)` | `col != 'escaped_val'` |
| `where_like(col, val)` | `col LIKE 'escaped_val'` |
| `where_ilike(col, val)` | `col ILIKE 'escaped_val'` |
| `where_between(col, lo, hi)` | `col BETWEEN 'escaped_lo' AND 'escaped_hi'` |
| `where_gt(col, val)` | `col > 'escaped_val'` |
| `where_gte(col, val)` | `col >= 'escaped_val'` |
| `where_lt(col, val)` | `col < 'escaped_val'` |
| `where_lte(col, val)` | `col <= 'escaped_val'` |
| `where_in(col, vals)` | `col IN (...)` — each value escaped |
| `where_not_in(col, vals)` | `col NOT IN (...)` — each value escaped |

### Unsafe functions — your responsibility

These functions perform no escaping. Passing user input directly into them will create a SQL injection vulnerability:

| Function | Risk |
|---|---|
| `where_raw(expr)` | Expression is inserted verbatim |
| `forge_sql(raw_sql)` | Executes any SQL you pass |
| `forge_exec_sql(raw_sql)` | Executes any SQL you pass |
| `forge_db_query(sql)` | No parameterization |
| `forge_db_exec(sql)` | No parameterization |

### Rule

Always use the named query builder methods for any value that originates from user input. Use `where_raw`, `forge_sql`, and the raw `forge_db_*` functions only for server-controlled expressions: `NOW()`, subqueries you write, column names from your own code, etc.

### Safe use of raw SQL

When you genuinely need raw SQL with a user-supplied value, use `forge_db_escape_str` to escape before interpolation:

```jda
fn safe_raw_query(user_input: []i8) -> &ForgeResult {
    let buf: &i8 = alloc_pages(1)
    let pos = 0i64
    let prefix = "SELECT * FROM logs WHERE ip = '"
    loop i in 0..prefix.len { buf[pos] = prefix[i]  pos = pos + 1 }
    let n = forge_db_escape_str(user_input, buf + pos)
    pos = pos + n
    buf[pos] = '\''
    pos = pos + 1
    ret forge_db_query(buf[0..pos])
}
```

This pattern is a last resort. If the named query builder methods cover your use case, prefer them.

---

## Cross-Site Scripting (XSS)

XSS happens when user-supplied content is written into an HTML response without escaping. The browser interprets it as markup or script and runs attacker-controlled code in the victim's browser.

### What Forge provides

`forge_html_escape(src: []i8, dst: &i8) -> i64` — escapes `&`, `<`, `>`, `"`, and `'` to their HTML entity equivalents. Returns the number of bytes written to `dst`.

`forge_h(src: []i8) -> []i8` — convenience wrapper: allocates a buffer, calls `forge_html_escape`, and returns the escaped slice. Use this inline in template expressions.

### Safe vs. unsafe rendering

```jda
// SAFE — user content is escaped before being placed in HTML
ctx_html(ctx, 200, "<h1>" + forge_h(ctx_form(ctx, "name")) + "</h1>")

// UNSAFE — raw user input is sent as HTML; a script tag will execute
ctx_html(ctx, 200, "<h1>" + ctx_form(ctx, "name") + "</h1>")
```

Apply `forge_h` to every piece of user-controlled data inserted into an HTML response: form fields, query parameters, database values that users wrote, URL path segments echoed back, error messages that repeat user input, etc.

### Attribute values

`forge_h` is safe for content inside double-quoted HTML attributes:

```jda
// SAFE
"<input value=\"" + forge_h(user_value) + "\">"

// UNSAFE — attribute is unquoted; an attacker can inject new attributes
"<input value=" + user_value + ">"
```

Always quote attribute values and escape the content.

### URL parameters in href and src

HTML-escaping is not enough for URLs in `href` or `src`. An attacker can supply `javascript:alert(1)` — which contains no HTML-special characters — and the browser will execute it.

Validate the URL scheme before rendering:

```jda
fn is_safe_url(url: []i8) -> bool {
    let http  = "http://"
    let https = "https://"
    if url.len >= https.len {
        let ok = true
        loop i in 0..https.len { if url[i] != https[i] { ok = false } }
        if ok { ret true }
    }
    if url.len >= http.len {
        let ok = true
        loop i in 0..http.len { if url[i] != http[i] { ok = false } }
        if ok { ret true }
    }
    if url.len > 0 && url[0] == '/' { ret true }
    ret false
}

fn render_redirect_link(ctx: i64, dest: []i8) {
    if !is_safe_url(dest) {
        ctx_html(ctx, 400, "Invalid redirect destination")
        ret
    }
    ctx_html(ctx, 200, "<a href=\"" + forge_h(dest) + "\">Continue</a>")
}
```

### JSON responses

A JSON response is safe from XSS as long as the `Content-Type` is `application/json`. If you serve JSON with `Content-Type: text/html`, the browser may parse it as HTML and execute embedded scripts. Never set JSON responses to a text/html content type.

---

## CSRF Protection

CSRF (Cross-Site Request Forgery) tricks an authenticated user's browser into making a state-changing request to your application from another origin. Because the browser automatically attaches cookies, the forged request arrives with valid session credentials.

### What Forge does automatically

The built-in CSRF middleware generates a per-session token, stores it in the session, and rejects any POST, PUT, or DELETE request that does not carry the matching token. GET requests are not checked (they must not have side effects).

### Enabling CSRF protection

Register the middleware in your middleware stack:

```jda
app_use(app, fn_addr(forge_logger))
app_use(app, fn_addr(forge_session_start))
app_use(app, fn_addr(forge_csrf))
```

### Including the token in HTML forms

```jda
fn handle_form(ctx: i64) {
    ctx_html(ctx, 200,
        "<form method=\"POST\" action=\"/submit\">" +
        ctx_csrf_field(ctx) +   // <input type="hidden" name="_csrf" value="...">
        "<input name=\"email\"><button>Submit</button>" +
        "</form>")
}
```

`ctx_csrf_field` returns a ready-to-embed hidden input. Always include it in every form that submits via POST, PUT, or DELETE.

### AJAX requests

Read the CSRF token from the session cookie or a meta tag and send it as a header:

```jda
// Server: emit the token in a meta tag so JavaScript can read it
fn render_page(ctx: i64) {
    let token = ctx_session_get(ctx, "_csrf_token")
    ctx_html(ctx, 200,
        "<meta name=\"csrf-token\" content=\"" + forge_h(token) + "\">")
}
```

```javascript
// Client JavaScript
const token = document.querySelector('meta[name="csrf-token"]').content;
fetch('/api/resource', {
    method: 'POST',
    headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
});
```

### Exempting API routes that use token authentication

CSRF protection is session-cookie-specific. API endpoints that authenticate via `Authorization: Bearer` headers are not vulnerable to CSRF because attackers cannot set arbitrary headers cross-origin. Register those routes before `forge_csrf`, or verify the bearer token manually in the handler:

```jda
// In main.jda — add forge_csrf after session middleware
app_use(app, fn_addr(forge_logger))
app_use(app, fn_addr(forge_session_start))
app_use(app, fn_addr(forge_csrf))
routes(app)
```

API routes are exempt because attackers cannot set `Authorization: Bearer` headers cross-origin — CSRF only applies to cookie-authenticated requests. Verify the bearer token inside the handler and return early before any state-mutating logic.

---

## Authentication

### Session-based authentication (cookie)

Sessions are the standard approach for browser-facing applications.

```jda
// 1. Register session middleware
app_use(app, fn_addr(forge_session_start))

// 2. On successful login, write the user identity into the session
fn handle_login_post(ctx: i64) {
    let email    = ctx_form(ctx, "email")
    let password = ctx_form(ctx, "password")
    let user     = user_find_by_email(email)
    if user == 0 || !forge_bcrypt_verify(password, user_password_hash(user)) {
        ctx_html(ctx, 401, "Invalid credentials")
        ret
    }
    ctx_session_set(ctx, "user_id", user_id_str(user))
    ctx_session_set(ctx, "role",    user_role(user))
    ctx_redirect(ctx, "/dashboard")
}

// 3. Read session values in protected handlers
fn handle_dashboard(ctx: i64) {
    let uid  = ctx_session_get(ctx, "user_id")
    let role = ctx_session_get(ctx, "role")
    // use uid and role
}

// 4. On logout, clear the session
fn handle_logout(ctx: i64) {
    ctx_session_clear(ctx)
    ctx_redirect(ctx, "/login")
}
```

### Require-login guard

Extract the authentication check into a helper so every protected handler looks the same:

```jda
fn require_login(ctx: i64) -> bool {
    let uid = ctx_session_get(ctx, "user_id")
    if uid.len == 0 {
        ctx_redirect(ctx, "/login")
        ret false
    }
    ret true
}

fn handle_settings(ctx: i64) {
    if !require_login(ctx) { ret }
    // proceed — user is authenticated
}
```

For role-based access:

```jda
fn require_role(ctx: i64, required: []i8) -> bool {
    if !require_login(ctx) { ret false }
    let role = ctx_session_get(ctx, "role")
    if !str_eq(role, required) {
        ctx_html(ctx, 403, "Forbidden")
        ret false
    }
    ret true
}

fn handle_admin_panel(ctx: i64) {
    if !require_role(ctx, "admin") { ret }
    // admin-only logic
}
```

### JWT authentication

Use JWT for stateless API authentication (mobile clients, service-to-service).

```jda
// 1. Set secret before registering middleware (minimum 32 characters)
forge_set_jwt_secret("your-secret-key-at-least-32-chars")
app_use(app, fn_addr(forge_jwt_auth))

// 2. Issue a token on login
fn handle_api_login(ctx: i64) {
    let user_id = authenticate_user(ctx)   // your logic
    if user_id.len == 0 {
        ctx_json(ctx, 401, "{\"error\":\"invalid credentials\"}")
        ret
    }
    let token = forge_jwt_sign(user_id, 3600)    // expires in 1 hour
    ctx_json(ctx, 200, "{\"token\":\"" + token + "\"}")
}

// 3. In protected handlers, read the subject claim set by the middleware
fn handle_protected_api(ctx: i64) {
    let sub = ctx_get(ctx, "jwt_sub")    // empty string if unauthenticated
    if sub.len == 0 {
        ctx_json(ctx, 401, "{\"error\":\"unauthorized\"}")
        ret
    }
    // sub is the user_id passed to forge_jwt_sign
}
```

JWT tokens expire; always set a short `exp`. Rotate the secret if it is compromised — all existing tokens immediately become invalid.

### HTTP Basic Auth

Suitable for protecting internal tools or development endpoints. Not appropriate for user-facing web applications.

```jda
forge_set_basic_auth("admin", "password")
app_use(app, fn_addr(forge_basic_auth))
```

Use a strong, randomly generated password. Serve only over HTTPS — Basic Auth credentials are base64-encoded (not encrypted) in transit.

---

## Secure HTTP Headers

HTTP response headers instruct browsers to enable security mechanisms. Missing headers leave users exposed to clickjacking, MIME sniffing, and protocol downgrade attacks.

### Enabling the built-in middleware

```jda
app_use(app, fn_addr(forge_secure_headers))
```

This sets the following headers on every response:

| Header | Value | Purpose |
|---|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Force HTTPS for 1 year |
| `X-Frame-Options` | `DENY` | Block clickjacking in older browsers |
| `X-Content-Type-Options` | `nosniff` | Prevent MIME-type sniffing |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limit referrer leakage |
| `Content-Security-Policy` | `default-src 'self'` | Block resources from external origins |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Disable unused browser features |

### Customizing the Content Security Policy

The default CSP (`default-src 'self'`) blocks all external resources. If your application loads scripts or styles from CDNs, extend it using a middleware that runs after `forge_secure_headers`:

```jda
app_use(app, fn_addr(forge_secure_headers))
app_use(app, fn_addr(my_csp))

fn my_csp(ctx: i64) {
    ctx_set_header(ctx, "Content-Security-Policy",
        "default-src 'self'; " +
        "script-src 'self' cdn.example.com; " +
        "style-src 'self' cdn.example.com; " +
        "img-src *; " +
        "font-src 'self' fonts.gstatic.com")
}
```

The later middleware's `Set-Header` call overwrites the value set by `forge_secure_headers`. See `overriding.md` — Pattern 3.

### Strict-Transport-Security

HSTS only takes effect when the response is served over HTTPS. Do not serve HSTS headers from an HTTP server — browsers will reject subsequent plain HTTP requests for the duration of `max-age`. In development, either skip `forge_secure_headers` or override HSTS to a short max-age.

---

## Rate Limiting

Rate limiting protects login endpoints, APIs, and any computationally expensive operation from brute-force attacks and abuse.

### Enabling the built-in middleware

```jda
app_use(app, fn_addr(forge_rate_limit))   // 100 requests per minute per IP
```

The default limit is 100 requests per minute per client IP. Requests that exceed the limit receive a `429 Too Many Requests` response.

### Raising the limit

Override the library function via a patch file (see `overriding.md` — Pattern 2):

```jda
// patches/forge_rate_limit.jda
//
// Why: default limit (100 req/min) is too low for our public API.
//      Raised to 500. Revisit if Redis-backed rate limiting is added.
// Overrides: forge_rate_limit in forge.jda

fn forge_rate_limit(ctx_ptr: i64) {
    let ip = ctx_ip(ctx_ptr)
    let key_buf = [128]i8
    let key_pos = 0i64
    let pfx = "rl:"
    loop i in 0..pfx.len { key_buf[key_pos] = pfx[i]  key_pos = key_pos + 1 }
    loop i in 0..ip.len  { key_buf[key_pos] = ip[i]   key_pos = key_pos + 1 }
    let key = key_buf[0..key_pos]
    let count = forge_cache_get(key)
    let n = str_to_i64(count)
    if n > 500 {
        ctx_too_many_requests(ctx_ptr)
        ret
    }
    forge_cache_set(key, i64_to_str(n + 1), 60)
}
```

Add `patches/` to your Makefile `SRC` list so the compiler sees it last and the patch shadows the library function.

### Per-route rate limits

For tighter limits on sensitive routes (login, password reset, OTP), implement a separate helper rather than changing the global limit:

```jda
fn rate_limit_strict(ctx: i64, limit: i64) -> bool {
    let ip = ctx_ip(ctx)
    let path = ctx_path(ctx)
    let key_buf = [256]i8
    let pos = 0i64
    let pfx = "rl_strict:"
    loop i in 0..pfx.len  { key_buf[pos] = pfx[i]   pos = pos + 1 }
    loop i in 0..path.len { key_buf[pos] = path[i]  pos = pos + 1 }
    loop i in 0..ip.len   { key_buf[pos] = ip[i]    pos = pos + 1 }
    let key = key_buf[0..pos]
    let count = forge_cache_get(key)
    let n = str_to_i64(count)
    if n >= limit {
        ctx_too_many_requests(ctx)
        ret false
    }
    forge_cache_set(key, i64_to_str(n + 1), 60)
    ret true
}

fn handle_login_post(ctx: i64) {
    if !rate_limit_strict(ctx, 5) { ret }   // 5 attempts per minute per IP per path
    // proceed with login logic
}
```

---

## Password Hashing

Storing passwords in plaintext or with a fast hash (MD5, SHA-256) allows an attacker who reads your database to recover all passwords. Always use an adaptive hash function designed for passwords.

### Forge's bcrypt functions

```jda
let hash  = forge_bcrypt_hash(password)       // returns hashed string
let valid = forge_bcrypt_verify(password, hash)  // returns bool
```

`forge_bcrypt_hash` uses bcrypt with an appropriate work factor. The returned hash string is self-contained and includes the salt — store it directly in the database column.

### forge_secure_password_set / forge_secure_password_verify

Convenience wrappers for password hashing. The column must be named `password_hash`.

```jda
fn user_create(email: []i8, password: []i8) -> bool {
    ret forge_attrs_new()
        .set("email", email)
        .secure_password(password)     // UFCS: forge_secure_password_set(a, password)
        .insert("users")
}

fn user_authenticate(email: []i8, password: []i8) -> bool {
    let res = forge_q("users").where_eq("email", email).first()
    if res.count == 0 { ret false }
    let id = forge_result_col(res, 0, "id")
    ret forge_secure_password_verify("users", id, password)
}
```

### Manual usage pattern

For full control, call the bcrypt functions directly:

```jda
fn user_create(email: []i8, password: []i8) -> bool {
    let hash = forge_bcrypt_hash(password)
    ret forge_attrs_new()
        .set("email",         email)
        .set("password_hash", hash)
        .insert("users")
}

fn user_authenticate(email: []i8, password: []i8) -> []i8 {
    let res = forge_q("users").where_eq("email", email).first()
    if res.count == 0 { ret "" }
    let stored_hash = forge_result_col(res, 0, "password_hash")
    if !forge_bcrypt_verify(password, stored_hash) { ret "" }
    ret forge_result_col(res, 0, "id")
}
```

Rules:
- Hash on registration, before the INSERT.
- Never log, print, or transmit plaintext passwords.
- Never store a password that has not been through `forge_bcrypt_hash`.
- On password change, hash the new password before the UPDATE.

---

## Secrets Management

Secrets (signing keys, database credentials, API keys) must not appear in source code or version control. An attacker with read access to your repository should not be able to connect to your database or forge session cookies.

### Environment files

Forge uses `.env.*` files loaded at startup. The convention:

| File | Committed to git? | Contains |
|---|---|---|
| `.env` | Yes | Non-secret shared defaults (e.g. `PORT=3000`) |
| `.env.test` | Yes | Test-specific config, no real secrets |
| `.env.development` | No | Real dev database URL, local secrets |
| `.env.staging` | No | Staging secrets |
| `.env.production` | No | Production secrets |

Add the sensitive files to `.gitignore`:

```
.env.development
.env.staging
.env.production
```

### Required secrets

Every Forge application requires at minimum:

```
APP_SECRET=<random 64-char hex string>
DATABASE_URL=postgres://user:pass@host/dbname
```

Generate `APP_SECRET` with a cryptographically random source:

```bash
openssl rand -hex 32
```

### Reading secrets in application code

```jda
fn app_config_load() {
    cfg.secret_key   = forge_env_get("APP_SECRET")
    cfg.database_url = forge_env_get("DATABASE_URL")
    if cfg.secret_key.len < 32 {
        forge_fatal("APP_SECRET must be at least 32 characters")
    }
}
```

Fail fast at startup if required secrets are missing or too short. Do not fall back to hardcoded defaults for secrets.

### What never belongs in source code

- Database passwords
- Session signing keys
- JWT secrets
- API keys for external services (payment processors, email providers, etc.)
- TLS private keys

---

## CORS

CORS (Cross-Origin Resource Sharing) controls which foreign origins can make requests to your API from browser JavaScript. A misconfigured CORS policy can allow any website to read your API responses using a logged-in user's credentials.

### Development only

The built-in `forge_cors` middleware is permissive by design — it allows all origins. Use it only in development:

```jda
// Development only
app_use(app, fn_addr(forge_cors))
```

Never deploy this to production.

### Production CORS with an origin whitelist

Replace `forge_cors` with your own middleware (Pattern 3 from `overriding.md`). Do not register `forge_cors`; register yours instead:

```jda
fn my_cors(ctx: i64) {
    let origin = ctx_header(ctx, "Origin")
    // Only reflect the header for origins you trust
    if str_eq(origin, "https://myapp.com") || str_eq(origin, "https://admin.myapp.com") {
        ctx_set_header(ctx, "Access-Control-Allow-Origin", origin)
        ctx_set_header(ctx, "Vary", "Origin")
    }
    ctx_set_header(ctx, "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    ctx_set_header(ctx, "Access-Control-Allow-Headers", "Content-Type, Authorization, X-CSRF-Token")
    // Allow cookies/session credentials only if the origin is trusted
    if str_eq(origin, "https://myapp.com") || str_eq(origin, "https://admin.myapp.com") {
        ctx_set_header(ctx, "Access-Control-Allow-Credentials", "true")
    }
}

// In main():
app_use(app, fn_addr(forge_logger))
app_use(app, fn_addr(forge_session_start))
app_use(app, fn_addr(forge_csrf))
app_use(app, fn_addr(my_cors))   // not forge_cors
```

### Preflight requests

Browsers send an OPTIONS request before cross-origin requests that carry credentials or non-simple headers. Handle it explicitly:

```jda
fn my_cors(ctx: i64) {
    let origin = ctx_header(ctx, "Origin")
    let trusted = str_eq(origin, "https://myapp.com")
    if trusted {
        ctx_set_header(ctx, "Access-Control-Allow-Origin", origin)
        ctx_set_header(ctx, "Vary", "Origin")
        ctx_set_header(ctx, "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        ctx_set_header(ctx, "Access-Control-Allow-Headers", "Content-Type, Authorization, X-CSRF-Token")
    }
    // Respond immediately to preflight
    if str_eq(ctx_method(ctx), "OPTIONS") {
        ctx_respond(ctx, 204, "")
        ret
    }
}
```

### Never do this in production

```jda
// UNSAFE — reflects any origin, including attacker.com
ctx_set_header(ctx, "Access-Control-Allow-Origin", origin)
ctx_set_header(ctx, "Access-Control-Allow-Credentials", "true")
```

Reflecting `Access-Control-Allow-Origin` with `Allow-Credentials: true` without checking the origin defeats CORS entirely.

---

## Signed Cookies

Regular cookies can be read and modified by the client. Signed cookies attach a tamper-proof signature so you can detect any modification. The signature is computed over the cookie value using `APP_SECRET` — without the secret, an attacker cannot produce a valid signature.

### Setting a signed cookie

```jda
ctx_cookie_signed_set(ctx, "remember_token", token, 2592000) // 30 days
```

Arguments: `(ctx, name, value, max_age_secs)`

The cookie is stored as `value.SIGNATURE` where `SIGNATURE` is 8 hex characters. If `APP_SECRET` is not set the cookie is stored unsigned.

### Reading a signed cookie

```jda
let token = ctx_cookie_signed_get(ctx, "remember_token")
// returns "" if the cookie is absent or the signature does not match
```

`ctx_cookie_signed_get` verifies the signature before returning the value. A missing or tampered cookie returns an empty string — treat it as "not signed in".

### Use cases

| Use case | Why signed over session? |
|---|---|
| "Remember me" tokens | Persists across browser close; no server-side session store needed |
| Prefilled form values | Safe to round-trip through the client |
| Tracking opt-out flags | Readable by JS but tamper-proof |

### Difference from session cookies

Session cookies (`ctx_session_*`) store data server-side and send only an opaque session ID. Signed cookies store data **client-side** (visible but not modifiable). Use sessions for sensitive data (user ID, CSRF token); use signed cookies for data that is safe to expose but must not be forged.

---

## Security Checklist

Use this before every production deployment.

### SQL

| | Topic | Requirement |
|---|---|---|
| [ ] | Query builder | Use named query builder methods (`where_eq`, `where_in`, etc.) for all user-supplied values |
| [ ] | Raw SQL | Never interpolate user input into `where_raw`, `forge_sql`, `forge_exec_sql`, `forge_db_query`, or `forge_db_exec` without `forge_db_escape_str` |

### XSS

| | Topic | Requirement |
|---|---|---|
| [ ] | HTML output | Every piece of user-supplied content is wrapped in `forge_h()` before insertion into HTML |
| [ ] | Attributes | All HTML attributes are double-quoted and their values are escaped |
| [ ] | URLs | Any URL echoed into `href` or `src` is validated with `is_safe_url` before rendering |
| [ ] | JSON | JSON responses use `Content-Type: application/json`, not `text/html` |

### CSRF

| | Topic | Requirement |
|---|---|---|
| [ ] | Middleware | `forge_csrf` is registered after `forge_session_start` |
| [ ] | Forms | Every HTML form with a POST/PUT/DELETE action includes `ctx_csrf_field(ctx)` |
| [ ] | AJAX | AJAX mutations send `X-CSRF-Token` header |
| [ ] | API routes | API routes using bearer auth are registered before `forge_csrf` or verified manually |

### Authentication

| | Topic | Requirement |
|---|---|---|
| [ ] | Session | `forge_session_start` is in the middleware stack before any handler that reads sessions |
| [ ] | Guards | Every protected route calls `require_login` or `require_role` before doing any work |
| [ ] | Logout | Logout handler calls `ctx_session_clear` |
| [ ] | JWT secret | `forge_set_jwt_secret` receives a secret of at least 32 characters |
| [ ] | Token expiry | JWT tokens are issued with short `exp` values (3600 seconds or less for sensitive ops) |

### Headers

| | Topic | Requirement |
|---|---|---|
| [ ] | Secure headers | `forge_secure_headers` is in the middleware stack |
| [ ] | CSP | Default CSP is tightened to enumerate all allowed external origins |
| [ ] | HSTS | Application is served over HTTPS so HSTS takes effect |

### Rate limiting

| | Topic | Requirement |
|---|---|---|
| [ ] | Global limit | `forge_rate_limit` is in the middleware stack |
| [ ] | Sensitive routes | Login, registration, password reset, and OTP endpoints have a tighter per-route limit |

### Passwords

| | Topic | Requirement |
|---|---|---|
| [ ] | Hashing | Passwords are hashed with `forge_bcrypt_hash` before INSERT and UPDATE |
| [ ] | No plaintext | Plaintext passwords are never stored, logged, or transmitted after initial receipt |

### Secrets

| | Topic | Requirement |
|---|---|---|
| [ ] | No hardcoded secrets | No passwords, keys, or tokens appear in source files |
| [ ] | Gitignore | `.env.development`, `.env.staging`, `.env.production` are in `.gitignore` |
| [ ] | APP_SECRET | `APP_SECRET` is at least 32 random bytes, different per environment |
| [ ] | Startup validation | Application fails to start if required secrets are missing or too short |

### CORS

| | Topic | Requirement |
|---|---|---|
| [ ] | No `forge_cors` in production | The permissive built-in CORS middleware is not registered in production |
| [ ] | Origin whitelist | Custom CORS middleware checks `Origin` against an explicit whitelist before reflecting it |
| [ ] | Credentials | `Access-Control-Allow-Credentials: true` is only set for whitelisted origins |
