# JDA Forge — Framework Completion Plan

Competitive target: Rails · Django · Gin/Fiber · FastAPI · Axum/Actix  
Current version: **v3.0 (4488 lines) — ALL PHASES COMPLETE**

---

## Status: Complete Feature Set

| Layer | Feature | Status |
|---|---|---|
| Routing | Params, wildcards, route groups, scoped middleware | ✅ |
| HTTP | JSON, form body, cookies, redirects, status helpers | ✅ |
| Middleware | Logger, CORS, rate-limit, secure-headers, request-id, no-cache | ✅ |
| Auth | JWT (HMAC-SHA256), Basic Auth, session middleware | ✅ |
| Security | CSRF protection, flash messages, HttpOnly cookies | ✅ |
| Real-time | WebSocket (RFC 6455), SSE (Server-Sent Events) | ✅ |
| Templates | ERB rendering via jda::erb | ✅ |
| Static files | Serve directory, MIME detection | ✅ |
| Database | PostgreSQL wire protocol, `forge_db_exec`, `forge_db_query` | ✅ |
| Migrations | `forge_migration_run`, tracks in forge_migrations table | ✅ |
| Admin UI | Auto-generated table view per registered model | ✅ |
| Background Jobs | spawn-based worker pool, `forge_job_enqueue` | ✅ |
| Mailer | Raw SMTP over TCP, sync + async send | ✅ |
| I18n | Flat-file key=value translations, `forge_t(ctx, key)` | ✅ |
| Project layout | Multi-file scaffold with Makefile concat pipeline | ✅ |
| **Query builder** | `forge_q("users").where(...).order(...).limit(n)` | ✅ ph1 |
| **Validations** | `forge_validate_presence/format/length/unique` | ✅ ph1 |
| **Callbacks** | `forge_model_before_save`, `forge_model_after_create` | ✅ ph1 |
| **Associations** | `forge_belongs_to`, `forge_has_many`, `forge_has_one` | ✅ ph1 |
| **Transactions** | `forge_db_begin/commit/rollback` | ✅ ph1 |
| **Soft delete** | `forge_soft_delete`, `forge_restore`, `forge_q_active` | ✅ ph1 |
| **Serializer** | `forge_model_to_json(row, fields[])` | ✅ ph1 |
| **Controller struct** | `ForgeController` with before/after filter chains | ✅ ph2 |
| **Before/after actions** | `forge_before_action`, `forge_after_action` | ✅ ph2 |
| **Strong params** | `forge_permit(ctx, allowed_keys[])` | ✅ ph2 |
| **respond_to** | `forge_respond_to(ctx, json_fn, html_fn)` | ✅ ph2 |
| **rescue_from** | `forge_rescue(ctx, error_type, handler_fn)` | ✅ ph2 |
| **Pagination** | `forge_paginate(res, page, per)` + Link headers | ✅ ph2 |
| **Layout system** | `forge_layout_set`, `forge_yield` | ✅ ph3 |
| **Partials** | `forge_partial(ctx, name, vars)` | ✅ ph3 |
| **content_for / yield** | `forge_content_for`, `forge_yield_content` | ✅ ph3 |
| **View helpers** | `forge_link_to`, `forge_form_for`, `forge_form_tag` | ✅ ph3 |
| **Path helpers** | `forge_path`, `forge_path_with_id` | ✅ ph3 |
| **Asset helpers** | `forge_css_tag`, `forge_js_tag` | ✅ ph3 |
| **Test runner** | `forge_test_run(suite)` — pass/fail summary | ✅ ph4 |
| **Test registration** | `forge_test(name, fn_ptr)` | ✅ ph4 |
| **Assertions** | `forge_assert_eq`, `forge_assert`, `forge_assert_nil` | ✅ ph4 |
| **HTTP request helpers** | `forge_test_get`, `forge_test_post` → ForgeTestResponse | ✅ ph4 |
| **Response assertions** | `forge_assert_status`, `forge_assert_body_has` | ✅ ph4 |
| **DB assertions** | `forge_assert_db_count`, `forge_assert_db_row` | ✅ ph4 |
| **Test DB setup** | `forge_test_db_truncate`, `forge_test_fixture` | ✅ ph4 |
| **Environments** | `FORGE_ENV` dev/test/prod constant | ✅ ph5 |
| **Config struct** | `ForgeEnvConfig` — DB URL, SMTP, secrets, log level | ✅ ph5 |
| **Env var API** | `forge_env_get(name)` reads process environment | ✅ ph5 |
| **Dotenv support** | `forge_dotenv_load(path)` parses `.env` file | ✅ ph5 |
| **Log levels** | `forge_log_debug/info/warn/error` respects `FORGE_LOG_LEVEL` | ✅ ph5 |
| **Concerns** | `ForgeConcern` struct with before/after callbacks | ✅ ph6 |
| **Timestampable** | `forge_concern_timestamps` — auto created_at/updated_at | ✅ ph6 |
| **Auditable** | `forge_audit_log(ctx, model, action)` | ✅ ph6 |
| **Taggable** | `forge_tags_add`, `forge_tags_for`, `forge_tags_find` | ✅ ph6 |
| **Multipart parsing** | `forge_multipart_file(ctx, field)` → ForgeUpload | ✅ ph7 |
| **Local storage** | `forge_storage_save`, `forge_storage_url` | ✅ ph7 |
| **Upload validation** | `forge_validate_upload_type`, `forge_validate_upload_size` | ✅ ph7 |
| **Response cache** | `forge_cache_response(ctx, key, ttl_sec)` — ETag + Cache-Control | ✅ ph8 |
| **Fragment cache** | `forge_cache_get`, `forge_cache_set`, `forge_cache_del` | ✅ ph8 |
| **Cache middleware** | `forge_cache_middleware` — 304 on If-None-Match hit | ✅ ph8 |
| **CLI generator** | `forge generate scaffold/model/controller/migration` | ✅ ph9 |

---

## Implementation Phases — All Complete

| Phase | What | Status | Lines |
|---|---|---|---|
| 1 | Model layer: query builder, validations, callbacks, associations, transactions, soft delete, serializer | ✅ | ~500 |
| 2 | Controller layer: before/after actions, strong params, respond_to, pagination, content negotiation | ✅ | ~300 |
| 3 | View layer: layouts, partials, content_for, helpers, path helpers | ✅ | ~250 |
| 4 | Testing framework: test runner, assertions, HTTP helpers, DB helpers | ✅ | ~400 |
| 5 | Environments + configuration: FORGE_ENV, dotenv, log levels, env var API | ✅ | ~200 |
| 6 | Concerns: timestampable, soft-delete, auditable, taggable | ✅ | ~300 |
| 7 | File uploads: multipart parsing, local storage | ✅ | ~200 |
| 8 | Caching: in-memory LRU, ETag, 304 support | ✅ | ~150 |
| 9 | CLI generator | ✅ | separate tool |

**Final forge.jda: 4488 lines**

---

## Comparison — All Phases Complete

| Feature | Rails | Django | **Forge** |
|---|---|---|---|
| Router + groups + scoped middleware | ✅ | ✅ | ✅ |
| JSON / form / multipart body parse | ✅ | ✅ | ✅ |
| Sessions + flash + CSRF | ✅ | ✅ | ✅ |
| Cookies (read/write/delete) | ✅ | ✅ | ✅ |
| Before/after action filters | ✅ | ✅ | ✅ |
| Strong params / permit | ✅ | Django forms | ✅ |
| respond_to / content negotiation | ✅ | ✅ | ✅ |
| rescue_from / error handlers | ✅ | ✅ | ✅ |
| Pagination | gem | built-in | ✅ |
| Query builder (where/order/limit) | ✅ | ✅ | ✅ |
| Model validations | ✅ | ✅ | ✅ |
| Model callbacks | ✅ | signals | ✅ |
| Associations (belongs_to/has_many) | ✅ | ✅ | ✅ |
| Transactions | ✅ | ✅ | ✅ |
| Soft delete | gem | ✅ | ✅ |
| Serializers (model → JSON) | ✅ | DRF | ✅ |
| ERB / template rendering | ✅ | ✅ | ✅ |
| Layouts + partials | ✅ | ✅ | ✅ |
| View helpers (link_to, form_for) | ✅ | template tags | ✅ |
| I18n | ✅ | ✅ | ✅ |
| Background jobs | ✅ | Celery | ✅ |
| Mailer | ✅ | ✅ | ✅ |
| WebSocket | Action Cable | Channels | ✅ |
| SSE | ✅ | ✅ | ✅ |
| Static files | ✅ | ✅ | ✅ |
| File uploads | Active Storage | ✅ | ✅ |
| Admin UI | — | ✅ | ✅ |
| Migrations | ✅ | ✅ | ✅ |
| Environments (dev/test/prod) | ✅ | ✅ | ✅ |
| Dotenv / secrets | ✅ | ✅ | ✅ |
| Test runner + request specs | RSpec | TestCase | ✅ |
| Model specs + DB assertions | ✅ | ✅ | ✅ |
| Caching (fragment + ETag) | ✅ | ✅ | ✅ |
| Concerns (timestampable, taggable) | gems | mixins | ✅ |
| CLI scaffold generator | ✅ | ✅ | ✅ |

**Out of scope** (separate language-level stdlib, not HTTP framework):
- Database drivers beyond PostgreSQL wire protocol
- GeoDjango / GIS
- Rich text editor (Action Text)
- Inbound email routing (Action Mailbox)
- Asset pipeline / JS/CSS bundling (handled by build tool)
- Code reloading in dev (handled by OS process restart)

---

## File Structure

```
forge.jda                 — the entire framework, single --include (4488 lines)
bin/forge                 — CLI generator script
scaffold/
  Makefile                — cat pipeline + jda build
  config.jda              — ForgeConfig, FORGE_ENV, secrets
  .env.example            — DATABASE_URL, SMTP_HOST, FORGE_ENV, APP_SECRET
  middleware/             — app-specific middleware files
  models/                 — model struct + validation + association files
  controllers/            — before/after action files
  views/                  — template strings + partials
  routes/                 — handler fns + route-registration helpers
  concerns/               — shared mixins (timestampable, soft-delete)
  db/migrations/          — NNN_name.sql migration files
  test/                   — test files using forge testing API
  main.jda                — app wiring + app_listen
```
