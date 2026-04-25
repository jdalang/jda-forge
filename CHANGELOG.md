# Changelog

All notable changes to JDA Forge are documented here.
Format: [Semantic Versioning](https://semver.org) — `MAJOR.MINOR.PATCH`

---

## [3.0.0] — 2026-04-22

### Added
- **Phases 1–9 complete** — framework now at parity with Rails/Django
- Phase 1 — Model layer: query builder (`forge_q`), validations, callbacks, associations, transactions, soft delete, JSON serializer
- Phase 2 — Controller layer: `ForgeController`, before/after filters, strong params (`forge_permit_json`), `respond_to`, pagination, content negotiation
- Phase 3 — View layer: layouts, partials, `content_for`/`yield`, `forge_link_to`, `forge_form_tag_*`, path helpers, asset helpers
- Phase 4 — Testing framework: `forge_test`, `forge_test_run`, `forge_assert_*`, HTTP request helpers, DB truncate/fixture helpers, test mode intercept
- Phase 5 — Environments: `FORGE_ENV`, `forge_dotenv_load`, `forge_env_get`, `forge_log_debug/info/warn/error`
- Phase 6 — Concerns: `forge_timestamps_create/update`, `forge_tags_*`, `forge_audit_log`
- Phase 7 — File uploads: `ctx_multipart_file`, `forge_upload_save`, `forge_validate_upload_type/size`
- Phase 8 — Caching: in-memory LRU (`forge_cache_get/set/del`), ETag middleware, 304 support
- Phase 9 — CLI generator: `forge generate scaffold/model/controller/migration`
- **Forgefile package system**: `forge install`, `forge add`, `forge update`, `forge list`, `Forgefile.lock`
- **`forge new <name>`**: full project skeleton with Makefile, config, env files, .gitignore
- **`forge release <version>`**: tag, push, GitHub release automation
- **`forge self-update [--version]`**: upgrade the CLI in-place
- **`install.sh`**: one-line installer with `--version` flag support
- Blog example app (`examples/blog/`): posts + comments CRUD, full middleware stack, migrations, tests

### Changed
- `ForgeResult` — added `col_names` field for column-aware JSON serialization
- `ctx_respond` — test mode intercept stores response instead of writing to socket
- `scaffold/Makefile` — `LIBS = $(wildcard libs/*.jda)` auto-discovery pattern

---

## [2.2.0] — 2026-04-10

### Added
- Background job worker pool (`forge_jobs_start`, `forge_job_enqueue`)
- I18n: flat-file translations (`forge_i18n_load`, `forge_t`)
- Mailer: raw SMTP over TCP (`forge_mail_send`, `forge_mail_send_async`)
- PostgreSQL wire protocol ORM (`forge_db_query`, `forge_db_exec`)
- Migrations: `forge_migration_run`, `forge_migrations` tracking table
- Admin UI: auto-generated table view per registered model
- Multi-file scaffold with Makefile concat pipeline

---

## [2.1.0] — 2026-04-05

### Added
- Sessions (cookie-based, in-memory store)
- Flash messages (`ctx_flash_set`, `ctx_flash_get`)
- CSRF protection (`forge_csrf`, `forge_csrf_token`)
- Server-Sent Events (`ctx_sse_start`, `forge_sse_send`)
- URL-encoded form body parsing (`ctx_form`)
- URL decode for query params and form fields
- Proxy-aware client IP (`X-Forwarded-For`, `X-Real-IP`)

---

## [2.0.0] — 2026-04-01

### Added
- Route groups with scoped middleware (`app_group`, `group_use`)
- WebSocket support (RFC 6455 handshake + framing)
- JWT authentication (`forge_jwt_auth`, `forge_set_jwt_secret`)
- Cookie read/write/delete
- Static file serving with MIME detection
- Middleware: rate-limit, secure-headers, no-cache, recover
- After-middleware (`app_after`)
- Custom 404 / 500 handlers

---

## [1.0.0] — 2026-03-28

### Added
- Initial release
- HTTP server on raw sockets (no libc)
- Routing: `app_get/post/put/delete/patch` with path params and wildcards
- Middleware chain (`app_use`)
- Context API: `ctx_param`, `ctx_query`, `ctx_header`, `ctx_json`, `ctx_html`, `ctx_redirect`
- Logger, CORS, Basic Auth middleware
- ERB template rendering via `jda::erb`
