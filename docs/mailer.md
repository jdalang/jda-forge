# Mailer

JDA Forge includes a built-in SMTP mailer. Mail is sent using the `ForgeMail` struct and either `forge_mail_send` (blocking) or `forge_mail_async` (non-blocking via the background job queue).

---

## Table of Contents

1. [Configuration](#1-configuration)
2. [Sending mail synchronously](#2-sending-mail-synchronously)
3. [Sending HTML mail](#3-sending-html-mail)
4. [Sending mail asynchronously](#4-sending-mail-asynchronously)
5. [Mail helper pattern](#5-mail-helper-pattern)
6. [ForgeMail struct reference](#6-forgemail-struct-reference)
7. [SMTP protocol notes](#7-smtp-protocol-notes)
8. [Environment setup](#8-environment-setup)
9. [Testing mail](#9-testing-mail)
10. [Delayed delivery](#10-delayed-delivery)
11. [Mailer previews in development](#11-mailer-previews-in-development)

---

## 1. Configuration

Call `forge_mailer_config` once during application startup, after `load_env()`:

```jda
fn main() {
    load_env()
    let cfg = app_config()

    forge_mailer_config(
        forge_env_get("SMTP_HOST"),
        587,                              // or str_to_i64(forge_env_get("SMTP_PORT"))
        forge_env_get("SMTP_USER"),
        forge_env_get("SMTP_PASS")
    )

    let app = app_new_config(cfg)
    // register routes ...
    app_listen(app, 8080)
}
```

Arguments: SMTP host, port (i64), username, password.

### Disabling the mailer

The mailer is automatically disabled when `cfg.smtp_host == ""`. Set it to empty in development and test to prevent real mail from being sent:

```jda
if forge_env_is("test") || forge_env_is("development") {
    cfg.smtp_host = ""
}
```

When the mailer is disabled, `forge_mail_send` returns `true` immediately without opening a connection, and `forge_mail_async` discards the message silently.

---

## 2. Sending mail synchronously

`forge_mail_send` connects to the SMTP server, sends the message, and blocks until it completes. It returns `true` on success and `false` on any error.

```jda
let mail: ForgeMail
mail.to      = "user@example.com"
mail.from    = "no-reply@myapp.com"
mail.subject = "Welcome to MyApp"
mail.body    = "Thanks for signing up!"
mail.html    = false

let ok = forge_mail_send(mail)
if !ok {
    forge_log(FORGE_LOG_WARN, "failed to send welcome email")
}
```

Use synchronous sending when the request should not complete until you know whether the mail succeeded — for example, a password reset where the email is the only delivery channel.

---

## 3. Sending HTML mail

Set `mail.html = true` to send `Content-Type: text/html`.

```jda
let mail: ForgeMail
mail.to      = user_email
mail.from    = "no-reply@myapp.com"
mail.subject = "Reset your password"
mail.body    = "<h1>Password Reset</h1><p>Click <a href=\"" + reset_url + "\">here</a> to reset.</p>"
mail.html    = true

forge_mail_send(mail)
```

The `body` field holds the entire email body regardless of whether `html` is `true` or `false`.

---

## 4. Sending mail asynchronously

`forge_mail_async` enqueues the message to the background job queue and returns immediately without blocking the request. The worker goroutine sends it in the background.

```jda
forge_mail_async(mail)
```

This requires `forge_jobs_start` to have been called at startup. See [background-jobs.md](background-jobs.md) for setup details.

Use `forge_mail_async` for all mail that is not on the critical path of the request — welcome emails, notification emails, digest emails, and so on.

---

## 5. Mail helper pattern

Keep mail-sending logic in a `mailers/` directory, one file per resource or domain concept. Each function constructs the `ForgeMail` struct and calls `forge_mail_send` or `forge_mail_async`.

```jda
// mailers/user_mailer.jda

fn mailer_send_welcome(email: []i8, name: []i8) -> bool {
    let mail: ForgeMail
    mail.to      = email
    mail.from    = "no-reply@myapp.com"
    mail.subject = "Welcome to MyApp, " + name + "!"
    mail.body    = "Hi " + name + ",\n\nThanks for signing up.\n"
    mail.html    = false
    ret forge_mail_send(mail)
}

fn mailer_send_password_reset(email: []i8, token: []i8) {
    let url = "https://myapp.com/reset/" + token
    let mail: ForgeMail
    mail.to      = email
    mail.from    = "no-reply@myapp.com"
    mail.subject = "Reset your password"
    mail.body    = "<p>Click <a href=\"" + url + "\">here</a> to reset your password.</p>"
    mail.html    = true
    forge_mail_async(mail)
}
```

Call the helper from a handler:

```jda
fn handle_users_create(ctx: i64) {
    // ... validate, save user ...
    mailer_send_welcome(email, name)
    ctx_redirect(ctx, "/dashboard")
}
```

This keeps handler code free of mail construction details and makes it easy to find all mail-sending logic.

---

## 6. ForgeMail struct reference

| Field | Type | Description |
|---|---|---|
| `to` | `[]i8` | Recipient email address |
| `from` | `[]i8` | Sender email address |
| `subject` | `[]i8` | Email subject line |
| `body` | `[]i8` | Email body (plain text or HTML) |
| `html` | `bool` | `true` sends `Content-Type: text/html`; `false` sends `text/plain` |

All fields are required. Leaving `to`, `from`, or `subject` empty will cause `forge_mail_send` to return `false`.

---

## 7. SMTP protocol notes

The Forge mailer connects on the configured port, sends `EHLO`, optionally authenticates with `AUTH LOGIN` when username and password are provided, then issues `MAIL FROM`, `RCPT TO`, and `DATA` in the standard SMTP sequence.

- **Port 587 (STARTTLS):** Supported. The mailer upgrades to TLS after the initial `EHLO` exchange. This is the recommended configuration for production.
- **Port 465 (implicit TLS):** Not supported. Do not configure port 465.
- **Unauthenticated relay:** Supported. Omit `SMTP_USER` and `SMTP_PASS` (or set them to empty strings) to skip `AUTH LOGIN`. Use this only for internal relay servers.

---

## 8. Environment setup

### Production

`.env.production`:
```
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=SG.your-api-key
```

For SendGrid, the username is always the literal string `apikey`; the password is the API key.

### Development and test

`.env.development` and `.env.test`: omit `SMTP_HOST` or leave it blank.

```
SMTP_HOST=
```

With an empty host, the mailer is disabled and no connection is attempted.

---

## 9. Testing mail

In test mode (`FORGE_ENV=test`) the mailer is disabled automatically when `SMTP_HOST` is empty. Do not assert on mail delivery in tests — test that the handler behaves correctly after mail would have been sent (correct redirect, flash message, database state).

```jda
// Good: test the handler outcome, not the email
fn test_signup_redirects_on_success() {
    let res = test_post("/users", "email=test@example.com&name=Alice")
    assert_eq(res.status, 302)
    assert_eq(res.location, "/dashboard")
}
```

### Capturing mail in tests

If you need to assert on mail content (subject, recipient, body), override `forge_mail_send` with a patch file that stores messages to a global slice instead of sending them. See [overriding.md](overriding.md) for the patching mechanism.

```jda
// test/mail_capture.jda  (patch file, compiled only in test builds)

let captured_mail: [16]ForgeMail
let captured_mail_count = 0i64

fn forge_mail_send(mail: ForgeMail) -> bool {
    captured_mail[captured_mail_count] = mail
    captured_mail_count = captured_mail_count + 1
    ret true
}
```

Then in a test:

```jda
fn test_welcome_email_subject() {
    captured_mail_count = 0
    test_post("/users", "email=test@example.com&name=Alice")
    assert_eq(captured_mail_count, 1i64)
    assert_eq(captured_mail[0].subject, "Welcome to MyApp, Alice!")
}
```

---

## 10. Delayed delivery

`forge_mail_send_in` schedules a mail to be sent after a delay. Internally it enqueues a background job that sleeps for `delay_ms` milliseconds and then sends:

```jda
// Send a follow-up nudge 24 hours after sign-up (24 * 60 * 60 * 1000 ms)
let delay_ms: i64 = 86400000
forge_mail_send_in(mail, delay_ms)
```

The calling goroutine returns immediately. Use this for timed sequences (onboarding drips, expiry warnings) without a separate scheduler.

---

## 11. Mailer previews in development

Mailer previews let you see a rendered mail in the browser without sending it. They are only active when `FORGE_ENV=development` — the preview routes return 404 in all other environments.

### Registering a preview

```jda
fn post_mailer_preview_new_post() -> ForgeMail {
    let mail: ForgeMail
    mail.to      = "preview@example.com"
    mail.from    = "blog@example.com"
    mail.subject = "New post: Hello World"
    mail.body    = "A new post has been published by Alice"
    ret mail
}
```

### Wiring up in main.jda

```jda
forge_mail_preview_register("new_post", fn_addr(post_mailer_preview_new_post))
app_get(app, "/_forge/mailers",       fn_addr(forge_mail_preview_handler))
app_get(app, "/_forge/mailers/:name", fn_addr(forge_mail_preview_handler))
```

### Browsing previews

| URL | What it shows |
|---|---|
| `/_forge/mailers` | Index listing all registered preview names |
| `/_forge/mailers/new_post` | Rendered preview for `new_post` |

The index page links to each preview so you can click through without remembering the names.
