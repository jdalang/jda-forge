# Background Jobs

Forge includes a worker pool for running tasks outside the HTTP request cycle. Common uses: sending email, processing uploads, cleaning up expired records, or any work that would otherwise block a response.

## Starting the worker pool

Call `forge_jobs_start` once at startup, after configuring the app but before calling `app_listen`:

```jda
fn main() {
    let app = app_new_config("config.toml")
    forge_jobs_start(4)    // start 4 worker goroutines
    app_listen(app, 8080)
}
```

Workers pull jobs off an internal channel and run them concurrently. The pool must be started before any jobs are enqueued.

## Defining a job

A job is a function with the signature `fn my_job(arg: i64)`. The `arg` is an opaque `i64` — typically a pointer cast from a heap-allocated struct.

```jda
fn send_welcome_email_job(arg: i64) {
    let user_ptr = arg as &ForgeUser
    // ... send email to user_ptr.email
}
```

Since Jda has no closures, pass data by allocating a struct with `alloc_pages` and casting its address to `i64`:

```jda
struct JobPayload {
    email:  []i8
    name:   []i8
}

fn welcome_job(arg: i64) {
    let p = arg as &JobPayload
    let mail: ForgeMail
    mail.to      = p.email
    mail.from    = "no-reply@myapp.com"
    mail.subject = "Welcome!"
    mail.body    = "Hi " + p.name
    mail.html    = false
    forge_mail_send(mail)
}

fn enqueue_welcome(email: []i8, name: []i8) {
    let p: &JobPayload = alloc_pages(1) as &JobPayload
    p.email = email
    p.name  = name
    forge_job_enqueue(fn_addr(welcome_job), p as i64)
}
```

## Enqueueing a job

```jda
forge_job_enqueue(fn_addr(my_job_fn), payload_ptr as i64)
```

- `fn_addr(fn_name)` — resolves the function address at runtime
- `arg` — an `i64` payload, usually a `&MyStruct` cast to `i64`

The call returns immediately. The job runs whenever a worker is free.

## Mail async helper

For the common case of sending mail in the background, Forge provides a shorthand that enqueues a mail send job without blocking the handler:

```jda
forge_mail_async(mail)
```

This is equivalent to manually enqueuing a mail job but requires no payload struct.

## Pattern: background processing in a handler

```jda
fn handle_users_create(ctx: i64) {
    let email = ctx_form(ctx, "email")
    let name  = ctx_form(ctx, "name")
    // ... save user to DB ...

    // Send welcome email in background — don't block the response
    enqueue_welcome(email, name)

    ctx_flash_set(ctx, "notice", "Account created!")
    ctx_redirect(ctx, "/dashboard")
}
```

The response is sent immediately; the email goes out whenever a worker picks up the job.

## Pattern: scheduled / periodic work

There is no built-in cron scheduler. For periodic work, enqueue a long-running job at startup that loops and sleeps:

```jda
fn cleanup_loop(arg: i64) {
    loop {
        forge_sleep_ms(3600000)    // every hour
        forge_exec_sql("DELETE FROM sessions WHERE expires_at < NOW()")
    }
}

fn main() {
    let app = app_new_config("config.toml")
    forge_jobs_start(4)
    forge_job_enqueue(fn_addr(cleanup_loop), 0)
    app_listen(app, 8080)
}
```

This occupies one worker for the lifetime of the process. Size the pool accordingly if you have several such loops.

## Error handling in jobs

Jobs run outside the HTTP request cycle — there is no automatic error recovery or panic handler. Handle all errors explicitly inside the job function:

```jda
fn my_job(arg: i64) {
    let ok = do_something()
    if !ok {
        forge_log(FORGE_LOG_ERROR, "job failed")
        // optionally re-enqueue or write to an error table
    }
}
```

A crashed job does not affect other workers or the HTTP server, but the job is not retried unless you re-enqueue it manually.

## Worker pool sizing

| Traffic level | Workers |
|---|---|
| Development / low traffic | 1–2 |
| Medium traffic | 4–8 |
| High-volume mail or processing | 8–16 |

Each job runs to completion before the worker picks up the next one. I/O-bound jobs (mail, DB writes) tolerate higher worker counts than CPU-bound jobs.
