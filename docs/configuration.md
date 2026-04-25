# Configuration

JDA Forge applications are configured through environment variables loaded from `.env` files. The active environment is determined by `FORGE_ENV`. Configuration is assembled once at startup in `app_config()` and passed to the framework.

---

## Environment detection

```jda
let env = forge_env_get("FORGE_ENV")   // "development", "staging", "production", "test"
forge_env_is("production")             // -> bool
```

`forge_env_get` returns an empty slice if the variable is not set. `forge_env_is` compares against the current value of `FORGE_ENV`. Both are available anywhere in your application code.

The conventional values are `development`, `staging`, `production`, and `test`. Forge itself only special-cases `test` (disabling SMTP). The rest of the environment-specific behaviour is in your own `app_config()`.

---

## Loading .env files

Forge does not load `.env` files automatically. Call `forge_dotenv_load` at the top of `main` before anything else reads environment variables.

```jda
fn load_env() {
    let env = forge_env_get("FORGE_ENV")
    if env.len == 0 { env = "development" }
    forge_dotenv_load(".env")                       // shared non-secret defaults
    if str_eq(env, "development")  { forge_dotenv_load(".env.development") }
    else if str_eq(env, "staging")     { forge_dotenv_load(".env.staging")     }
    else if str_eq(env, "production")  { forge_dotenv_load(".env.production")  }
    else if str_eq(env, "test")        { forge_dotenv_load(".env.test")        }
}
```

`forge_dotenv_load` reads the named file and sets any variables not already present in the process environment. Variables already set in the shell environment take precedence over the file — this means you can override any value by exporting it before launching the process.

Call `load_env()` before `app_config()` so all variables are available when the config struct is populated.

---

## .env file conventions

| File | Commit to git? | Purpose |
|---|---|---|
| `.env` | Yes | Shared non-secret defaults (timeouts, feature flags, port) |
| `.env.development` | No | Local dev database URL, debug secrets |
| `.env.staging` | No | Staging server credentials |
| `.env.production` | No | Production secrets |
| `.env.test` | Yes | Test database URL — no real credentials |

`.env` and `.env.test` are safe to commit because they contain no secrets. All other environment files hold real credentials and must be listed in `.gitignore`.

### Example `.env`

```
APP_PORT=8080
UPLOAD_DIR=uploads/
FORGE_ENV=development
```

### Example `.env.development`

```
DATABASE_URL=postgres://dev_user:dev_pass@localhost:5432/myapp_development
APP_SECRET=dev-secret-key-not-for-production-use-only
SMTP_HOST=localhost
SMTP_PORT=1025
REDIS_URL=redis://localhost:6379/0
UPLOAD_DIR=uploads/
```

### Example `.env.staging`

```
DATABASE_URL=postgres://app:REPLACE_ME@staging-db.example.com:5432/myapp_staging
APP_SECRET=REPLACE_ME_32_chars_minimum
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=no-reply@example.com
SMTP_PASS=REPLACE_ME
REDIS_URL=redis://staging-redis.example.com:6379/0
UPLOAD_DIR=/var/myapp/uploads/
```

### Example `.env.production`

```
DATABASE_URL=postgres://app:REPLACE_ME@prod-db.example.com:5432/myapp_production
APP_SECRET=REPLACE_ME_32_chars_minimum
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=no-reply@example.com
SMTP_PASS=REPLACE_ME
REDIS_URL=redis://prod-redis.example.com:6379/0
UPLOAD_DIR=/var/myapp/uploads/
```

### Example `.env.test`

```
DATABASE_URL=postgres://test_user:test_pass@localhost:5432/myapp_test
APP_SECRET=test-secret-key-not-real
```

---

## app_config()

`app_config` reads all environment variables and assembles a `ForgeConfig` struct. Define it in your application and call it from `main` after `load_env()`.

```jda
fn app_config() -> ForgeConfig {
    let cfg = forge_default_config()
    cfg.db_url     = forge_env_get("DATABASE_URL")
    cfg.smtp_host  = forge_env_get("SMTP_HOST")
    cfg.smtp_port  = forge_env_get("SMTP_PORT")
    cfg.smtp_user  = forge_env_get("SMTP_USER")
    cfg.smtp_pass  = forge_env_get("SMTP_PASS")
    cfg.secret_key = forge_env_get("APP_SECRET")    // session signing key
    cfg.upload_dir = forge_env_get("UPLOAD_DIR")
    cfg.redis_url  = forge_env_get("REDIS_URL")
    if forge_env_is("test") or forge_env_is("development") { cfg.smtp_host = "" }
    if forge_env_is("development") { forge_log_level_set(FORGE_LOG_DEBUG) }
    else                           { forge_log_level_set(FORGE_LOG_INFO)  }
    ret cfg
}
```

Setting `cfg.smtp_host` to an empty string disables outbound email for test and development environments. In `test`, Forge captures emails in memory regardless; in `development`, clearing the host prevents accidental sends to real addresses during local work.

---

## ForgeConfig fields

| Field | Env var | Description |
|---|---|---|
| `db_url` | `DATABASE_URL` | PostgreSQL connection string |
| `smtp_host` | `SMTP_HOST` | Mail server hostname — set to `""` to disable |
| `smtp_port` | `SMTP_PORT` | Mail server port (default 587) |
| `smtp_user` | `SMTP_USER` | Mail auth username |
| `smtp_pass` | `SMTP_PASS` | Mail auth password |
| `secret_key` | `APP_SECRET` | Session signing secret — minimum 32 characters |
| `upload_dir` | `UPLOAD_DIR` | Directory for file uploads |
| `redis_url` | `REDIS_URL` | Redis connection string for caching and rate limiting |

`forge_default_config()` fills in sensible defaults (port 587 for SMTP, `uploads/` for upload directory). Override only the fields your application needs.

`APP_SECRET` must be at least 32 characters. A short or predictable secret allows session forgery. Generate one with:

```bash
openssl rand -hex 32
```

---

## Log levels

```jda
forge_log_level_set(FORGE_LOG_DEBUG)   // debug + info + warn + error
forge_log_level_set(FORGE_LOG_INFO)    // info + warn + error
forge_log_level_set(FORGE_LOG_WARN)    // warn + error
forge_log_level_set(FORGE_LOG_ERROR)   // error only
```

The standard pattern is `DEBUG` in development and `INFO` in all other environments. Set the level in `app_config()` so it applies before the server starts accepting connections.

Each level includes all levels above it in severity — `FORGE_LOG_WARN` also outputs errors.

---

## Port configuration

The port defaults to 8080. Override it with `APP_PORT`:

```jda
let port_str = forge_env_get("APP_PORT")
let port = 8080i64
if port_str.len > 0 { port = str_to_i64(port_str) }
app_listen(app, port)
```

Set `APP_PORT` in `.env` or export it before starting the server:

```bash
APP_PORT=3000 ./app
```

---

## Accessing environment variables

```jda
let val    = forge_env_get("MY_VAR")          // returns "" if not set
let is_set = forge_env_get("MY_VAR").len > 0  // check presence
```

`forge_env_get` never panics — it returns an empty `[]i8` slice when the variable is absent. Check `.len` before using a value that has no sensible default.

---

## Quick reference

| Function | What it does |
|---|---|
| `forge_env_get(name)` | Read environment variable, `""` if unset |
| `forge_env_is(name)` | Compare `FORGE_ENV` to string, returns `bool` |
| `forge_dotenv_load(path)` | Load `.env` file, existing env vars take precedence |
| `forge_default_config()` | Return `ForgeConfig` with built-in defaults |
| `forge_log_level_set(level)` | Set log verbosity |

**Log level constants:** `FORGE_LOG_DEBUG`, `FORGE_LOG_INFO`, `FORGE_LOG_WARN`, `FORGE_LOG_ERROR`

**Startup order:** `load_env()` → `app_config()` → `app_listen()`

**Files to commit:** `.env`, `.env.test`, `Forgefile`, `Forgefile.lock`

**Files to gitignore:** `.env.development`, `.env.staging`, `.env.production`
