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

---

## Retry on failure

### Automatic retry with a fixed attempt count

`forge_job_enqueue_retry` retries a failed job up to `max_retries` times:

```jda
forge_job_enqueue_retry(fn_addr(my_job), payload as i64, 3)
```

If the job function returns without error it is considered successful. If it panics or the function itself calls retry logic, the retry counter ticks down until exhausted.

### Exponential backoff retry

`forge_job_enqueue_retry_backoff` doubles the delay between each attempt:

```jda
// up to 5 retries, starting with a 500 ms delay (then 1s, 2s, 4s, 8s)
forge_job_enqueue_retry_backoff(fn_addr(send_webhook), payload as i64, 5, 500)
```

Arguments: `(fn_ptr, arg, max_retries, base_delay_ms)`

### discard_on — stop retrying on a known error

`forge_job_enqueue_retry_discard` pairs a retry policy with a discard predicate. If the discard function returns `true`, further retries are skipped and the job is silently dropped:

```jda
fn should_discard(arg: i64) -> bool {
    // Discard if the user no longer exists.
    let p = arg as &WelcomePayload
    let res = user_find(p.user_id)
    ret forge_result_empty(res)
}

forge_job_enqueue_retry_discard(fn_addr(welcome_job), payload as i64, 3, fn_addr(should_discard))
```

Arguments: `(fn_ptr, arg, max_retries, discard_fn_ptr)`

---

## Delayed execution

`forge_job_enqueue_in` schedules a job to run after a wall-clock delay:

```jda
// Send a follow-up email 30 minutes after sign-up (30 * 60 * 1000 ms)
forge_job_enqueue_in(fn_addr(followup_email_job), payload as i64, 1800000)
```

The calling goroutine is not blocked. Internally, a short-lived wrapper job sleeps for the delay and then calls the target job on a worker.

---

## Job lifecycle callbacks

Register hooks that run around every job execution in the process. Useful for logging, APM traces, or resetting request-scoped state between jobs.

```jda
fn on_job_before(arg: i64) {
    forge_log(FORGE_LOG_DEBUG, "job starting")
}
fn on_job_after(arg: i64) {
    forge_log(FORGE_LOG_DEBUG, "job finished")
}

fn main() {
    forge_jobs_start(4)
    forge_job_before_perform(fn_addr(on_job_before))
    forge_job_after_perform (fn_addr(on_job_after))
    // ...
}
```

`arg` in the hook functions receives the same `i64` payload as the job itself.

| Function | Description |
|---|---|
| `forge_job_before_perform(fn_ptr)` | Called before every job runs |
| `forge_job_after_perform(fn_ptr)` | Called after every job completes |

Up to 8 before hooks and 8 after hooks can be registered.
