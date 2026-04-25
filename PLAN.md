# JDA Forge — Framework Completion Plan

Competitive target: Rails · Django · Gin/Fiber · FastAPI · Axum/Actix  
Current version: v2.2 (2320 lines)

---

## Status: What We Have

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
| Database | PostgreSQL wire protocol, `forge_db_exec`, `forge_db_query` | ✅ basic |
| Migrations | `forge_migration_run`, tracks in forge_migrations table | ✅ basic |
| Admin UI | Auto-generated table view per registered model | ✅ basic |
| Background Jobs | spawn-based worker pool, `forge_job_enqueue` | ✅ |
| Mailer | Raw SMTP over TCP, sync + async send | ✅ |
| I18n | Flat-file key=value translations, `forge_t(ctx, key)` | ✅ |
| Project layout | Multi-file scaffold with Makefile concat pipeline | ✅ |

---

## Gap Analysis: What Is Missing

### Phase 1 — Model Layer (Active Record parity)

| Feature | Rails equivalent | Description |
|---|---|---|
| **Query builder** | `where`, `order`, `limit`, `joins` | Chainable SQL builder: `forge_q("users").where("email", "=", val).limit(10)` |
| **Model struct pattern** | `class User < ApplicationRecord` | `ForgeModel` base: table name, field list, read/write from DB row |
| **Validations** | `validates :email, presence: true` | `forge_validate_presence`, `forge_validate_format`, `forge_validate_length`, `forge_validate_unique`, custom validator fn |
| **Callbacks** | `before_save`, `after_create` | `forge_model_before_save(fn)`, `forge_model_after_create(fn)` hooks stored per-model |
| **Associations** | `belongs_to`, `has_many`, `has_one` | Adds lookup helpers: `forge_belongs_to(model, fk)` generates `find_user_for_post(post)` |
| **Scopes** | `scope :published, -> { where... }` | Named reusable query fragments registered on model |
| **Transactions** | `ActiveRecord::Base.transaction` | `forge_db_begin`, `forge_db_commit`, `forge_db_rollback` |
| **Soft delete** | `acts_as_paranoid` | `deleted_at` column, `forge_soft_delete`, `forge_restore`, default scope excludes deleted |
| **Serializer** | `jbuilder`, `as_json` | `forge_model_to_json(row, fields[])` builds JSON from ForgeDbRow |

### Phase 2 — Controller Layer (Action Controller parity)

| Feature | Rails equivalent | Description |
|---|---|---|
| **Controller struct** | `class UsersController < ApplicationController` | `ForgeController` with `before_actions[]`, `after_actions[]`, action dispatch |
| **Before/after actions** | `before_action :require_login` | Filter chain runs before/after named actions; supports `only:` / `except:` |
| **Strong params** | `params.require(:user).permit(:email)` | `forge_permit(ctx, allowed_keys[])` — strips keys not in whitelist, returns filtered JSON |
| **respond_to** | `respond_to { |f| f.json { } f.html { } }` | `forge_respond_to(ctx, json_fn, html_fn)` — dispatches on Accept header |
| **rescue_from** | `rescue_from ActiveRecord::NotFound` | Per-controller error handler: `forge_rescue(ctx, error_type, handler_fn)` |
| **Pagination helper** | `@users.page(params[:page]).per(20)` | `forge_paginate(res, page, per)` slices ForgeResult; adds Link headers |
| **Content negotiation** | `format.json { render json: @user }` | `ctx_format(ctx)` returns `"json"`, `"html"`, `"xml"` based on Accept |

### Phase 3 — View Layer (Action View parity)

| Feature | Rails equivalent | Description |
|---|---|---|
| **Layout system** | `layout "application"` | `forge_layout_set(ctx, name)`, `forge_yield(ctx)` — wraps response body in layout template |
| **Partials** | `render partial: "user"` | `forge_partial(ctx, name, vars)` — renders a sub-template and returns []i8 |
| **content_for / yield** | `content_for :title` | `forge_content_for(ctx, key, content)`, `forge_yield_content(ctx, key)` |
| **View helpers** | `link_to`, `form_for`, `form_tag` | `forge_link_to(text, url)`, `forge_form_for(action, method, csrf_token, body)` |
| **Path helpers** | `users_path`, `user_path(id)` | `forge_path(ctx, "users")`, `forge_path_with_id(ctx, "users", id)` |
| **Asset helpers** | `stylesheet_link_tag`, `javascript_include_tag` | `forge_css_tag(path)`, `forge_js_tag(path)` — emits `<link>` / `<script>` with cache-busting |

### Phase 4 — Testing Framework (RSpec / Django TestCase parity)

| Feature | Rails/RSpec equivalent | Description |
|---|---|---|
| **Test runner** | `rspec` / `rails test` | `forge_test_run(suite)` — runs all registered tests, prints pass/fail summary |
| **Test registration** | `describe "..." do it "..." end` | `forge_test(name, fn_ptr)` registers a test case |
| **Assertions** | `expect(x).to eq(y)` | `forge_assert_eq(a, b, msg)`, `forge_assert(cond, msg)`, `forge_assert_nil(val)` |
| **HTTP request helper** | `get "/users"`, `post "/users"` | `forge_test_get(app, path)`, `forge_test_post(app, path, body)` → ForgeTestResponse |
| **Response assertions** | `expect(response).to have_http_status(200)` | `forge_assert_status(res, 200)`, `forge_assert_body_contains(res, "Alice")` |
| **Model assertions** | `expect(User.count).to eq(1)` | `forge_assert_db_count(table, expected)`, `forge_assert_db_row(table, key, val)` |
| **Test DB setup** | `DatabaseCleaner`, `FactoryBot` | `forge_test_db_truncate(tables[])`, `forge_test_fixture(table, data)` |
| **Environment: test** | `Rails.env.test?` | `FORGE_ENV == "test"` disables SMTP, uses in-memory job queue, verbose errors |

### Phase 5 — Environment & Configuration

| Feature | Rails equivalent | Description |
|---|---|---|
| **Environments** | `config/environments/development.rb` | `FORGE_ENV` constant: `"development"` / `"test"` / `"production"` |
| **Config struct** | `Rails.application.config` | `ForgeEnvConfig` loaded at boot: DB URL, SMTP, secrets, log level |
| **Config from env vars** | `ENV["DATABASE_URL"]` | `forge_env_get(name)` reads process environment variable via syscall |
| **Credentials/secrets** | `config/credentials.yml.enc` | `forge_secret(name)` reads from `FORGE_SECRETS` env var or `.env` file |
| **Dotenv support** | `dotenv` gem | `forge_dotenv_load(path)` parses `.env` file and sets process env vars |
| **Log levels** | `Rails.logger.info` | `forge_log_debug`, `forge_log_info`, `forge_log_warn`, `forge_log_error` — respects `FORGE_LOG_LEVEL` |
| **Per-env middleware** | Skip mailer/jobs in test | Checked via `FORGE_ENV`; `forge_mailer_disabled` in test, real SMTP in production |

### Phase 6 — Concerns & Shared Behavior

| Feature | Rails equivalent | Description |
|---|---|---|
| **Concerns** | `module Concerns::Timestampable` | `ForgeConcern` struct holding before/after callbacks + helper fns; mixed into model/controller |
| **Timestampable** | `include Timestamps` | Adds `created_at`, `updated_at` columns; auto-sets on insert/update |
| **Soft-deletable** | `acts_as_paranoid` | Adds `deleted_at`; `forge_soft_delete` sets it; default queries exclude it |
| **Auditable** | `has_paper_trail` | `forge_audit_log(ctx, model, action)` writes to `forge_audit_log` table |
| **Taggable** | `acts_as_taggable` | `forge_tags_add(model, id, tag)`, `forge_tags_for(model, id)`, `forge_tags_find(model, tag)` |

### Phase 7 — File Uploads & Storage

| Feature | Rails equivalent | Description |
|---|---|---|
| **Multipart parsing** | `params[:file]` | `forge_multipart_file(ctx, field)` → `ForgeUpload{filename, content_type, data, size}` |
| **Local storage** | `has_one_attached :avatar` | `forge_storage_save(upload, dest_path)` writes to filesystem |
| **Storage URL** | `url_for(user.avatar)` | `forge_storage_url(path)` returns `/uploads/<path>` |
| **Image validation** | `validates :image, content_type: "image/*"` | `forge_validate_upload_type(upload, allowed[])` |
| **Size limit** | `validates :file, size: { less_than: 5.megabytes }` | `forge_validate_upload_size(upload, max_bytes)` |

### Phase 8 — Caching

| Feature | Rails equivalent | Description |
|---|---|---|
| **Response cache** | `expires_in 10.minutes` | `forge_cache_response(ctx, key, ttl_sec)` — ETag + Cache-Control headers |
| **Fragment cache** | `cache @user` | `forge_cache_get(key)`, `forge_cache_set(key, val, ttl)` — in-memory LRU |
| **Cache middleware** | `config.action_dispatch.rack_cache` | `forge_cache_middleware` — checks If-None-Match, returns 304 on hit |
| **Cache invalidation** | `expire_fragment` | `forge_cache_del(key)`, `forge_cache_del_prefix(prefix)` |

### Phase 9 — CLI Generator

| Feature | Rails equivalent | Description |
|---|---|---|
| **Scaffold** | `rails generate scaffold User email:string` | `forge generate scaffold <name> <field:type>…` → creates model/controller/routes/migration files |
| **Model** | `rails generate model User` | `forge generate model <name> <fields>` → model jda file + migration SQL |
| **Controller** | `rails generate controller Users` | `forge generate controller <name>` → handler file with CRUD stubs + route registration fn |
| **Migration** | `rails generate migration AddEmailToUsers` | `forge generate migration <name>` → timestamped migration file |

---

## Implementation Phases

| Phase | What | Priority | Lines est. |
|---|---|---|---|
| 1 | Model layer: query builder, validations, callbacks, associations, transactions, soft delete, serializer | **High** | ~500 |
| 2 | Controller layer: before/after actions, strong params, respond_to, pagination, content negotiation | **High** | ~300 |
| 3 | View layer: layouts, partials, content_for, helpers, path helpers | **Medium** | ~250 |
| 4 | Testing framework: test runner, assertions, HTTP helpers, DB helpers | **High** | ~400 |
| 5 | Environments + configuration: FORGE_ENV, dotenv, log levels, env var API | **High** | ~200 |
| 6 | Concerns: timestampable, soft-delete, auditable, taggable | **Medium** | ~300 |
| 7 | File uploads: multipart parsing, local storage | **Medium** | ~200 |
| 8 | Caching: in-memory LRU, ETag, 304 support | **Medium** | ~150 |
| 9 | CLI generator | **Low** | separate tool |

**Estimated final forge.jda: ~4400 lines**

---

## Comparison After All Phases Complete

| Feature | Rails | Django | **Forge** |
|---|---|---|---|
| Router + groups + scoped middleware | ✅ | ✅ | ✅ |
| JSON / form / multipart body parse | ✅ | ✅ | ✅ ph7 |
| Sessions + flash + CSRF | ✅ | ✅ | ✅ |
| Cookies (read/write/delete) | ✅ | ✅ | ✅ |
| Before/after action filters | ✅ | ✅ | ✅ ph2 |
| Strong params / permit | ✅ | Django forms | ✅ ph2 |
| respond_to / content negotiation | ✅ | ✅ | ✅ ph2 |
| rescue_from / error handlers | ✅ | ✅ | ✅ ph2 |
| Pagination | gem | built-in | ✅ ph2 |
| Query builder (where/order/limit) | ✅ | ✅ | ✅ ph1 |
| Model validations | ✅ | ✅ | ✅ ph1 |
| Model callbacks | ✅ | signals | ✅ ph1 |
| Associations (belongs_to/has_many) | ✅ | ✅ | ✅ ph1 |
| Transactions | ✅ | ✅ | ✅ ph1 |
| Soft delete | gem | ✅ | ✅ ph6 |
| Serializers (model → JSON) | ✅ | DRF | ✅ ph1 |
| ERB / template rendering | ✅ | ✅ | ✅ |
| Layouts + partials | ✅ | ✅ | ✅ ph3 |
| View helpers (link_to, form_for) | ✅ | template tags | ✅ ph3 |
| I18n | ✅ | ✅ | ✅ |
| Background jobs | ✅ | Celery | ✅ |
| Mailer | ✅ | ✅ | ✅ |
| WebSocket | Action Cable | Channels | ✅ |
| SSE | ✅ | ✅ | ✅ |
| Static files | ✅ | ✅ | ✅ |
| File uploads | Active Storage | ✅ | ✅ ph7 |
| Admin UI | — | ✅ | ✅ basic→ph6 |
| Migrations | ✅ | ✅ | ✅ |
| Environments (dev/test/prod) | ✅ | ✅ | ✅ ph5 |
| Dotenv / secrets | ✅ | ✅ | ✅ ph5 |
| Test runner + request specs | RSpec | TestCase | ✅ ph4 |
| Model specs + DB assertions | ✅ | ✅ | ✅ ph4 |
| Caching (fragment + ETag) | ✅ | ✅ | ✅ ph8 |
| Concerns (timestampable, taggable) | gems | mixins | ✅ ph6 |
| CLI scaffold generator | ✅ | ✅ | ph9 |
| ORM (not out of scope) | ✅ | ✅ | ✅ |

**Out of scope** (separate language-level stdlib, not HTTP framework):  
- Database drivers beyond PostgreSQL wire protocol  
- GeoDjango / GIS  
- Rich text editor (Action Text)  
- Inbound email routing (Action Mailbox)  
- Asset pipeline / JS/CSS bundling (handled by build tool)  
- Code reloading in dev (handled by OS process restart)

---

## File Structure After All Phases

```
forge.jda                 — the entire framework, single --include
scaffold/
  Makefile                — cat pipeline + jda build
  config.jda              — ForgeConfig, FORGE_ENV, secrets
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

---

*Ready to implement. Start with Phase 1 (Model layer) or Phase 5 (Environments) — confirm which to begin.*
