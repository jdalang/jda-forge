# Forge Performance

Why Forge is slow compared to Rails, and how to fix it. Issues are ordered by impact.

---

## Issue 1 — New PostgreSQL connection per query

### What happens

Every call to `forge_db_query` / `forge_db_exec` opens a brand-new TCP connection to PostgreSQL, does the full authentication handshake, runs the query, and closes:

```jda
fn forge_pg_query(...) {
    let fd = forge_pg_connect(host, port, user, pass, dbname)  // TCP + auth every time
    ...
    // fd closed at end of function
}
```

### Cost

A fresh Postgres connection costs ~20–60ms (TCP 3-way handshake + startup packet + auth exchange). A typical page load runs 2–4 queries. That's 40–240ms of pure connection overhead before any query executes — this alone accounts for most of the ~90ms serial latency.

`psql postgres://... -c "SELECT 1"` measures ~64ms round-trip on localhost, all of which is connection overhead.

### Fix — persistent connection per worker

Keep one open PostgreSQL connection in a global and reuse it:

```jda
let g_pg_fd: i32 = -1

fn forge_pg_get_conn() -> i32 {
    if g_pg_fd >= 0 { ret g_pg_fd }
    g_pg_fd = forge_pg_connect(g_forge_db_host, g_forge_db_port,
                                g_forge_db_user, g_forge_db_pass, g_forge_db_name)
    ret g_pg_fd
}

fn forge_pg_query(...) {
    let fd = forge_pg_get_conn()
    // if fd < 0 or query fails with broken-pipe, reconnect once and retry
    ...
}
```

For a multi-worker server, each worker holds its own persistent connection. This reduces connection overhead from O(queries) to O(1) at startup.

Expected speedup: **5–10× for any DB-heavy page.**

---

## Issue 2 — Single-threaded server

### What happens

`app_listen` handles one request fully before accepting the next:

```jda
fn app_listen(app: &ForgeApp, port: i32) {
    loop {
        let cfd = syscall(accept, lfd, ...)   // wait for connection
        if cfd >= 0 { forge_handle_fd(cfd) }  // handle synchronously — blocks accept loop
    }
}
```

`spawn {}` is a compiler stub that runs the body **inline**, not in a new thread:

```awk
# compiler/jda line 1150:
# spawn { body } - execute body inline (single-threaded stub)
```

Under any concurrent load (`ab -c 2`), the kernel's accept backlog fills and connections get reset.

### Fix — spawn a thread per accepted connection

#### In the runtime (`forge.jda`):
```jda
fn app_listen(app: &ForgeApp, port: i32) {
    let lfd = TcpListener__bind("0.0.0.0", port)
    loop {
        let cfd = syscall(accept, lfd, sa, salen, 0, 0, 0) as i32
        if cfd >= 0 {
            let fd_box: &i32 = alloc_pages(1)
            fd_box[0] = cfd
            spawn { forge_handle_fd(fd_box[0]) }   // needs real spawn
        }
    }
}
```

#### In the compiler (`~/.jda/bin/jda`):
`spawn { body }` must create a real POSIX thread. The body needs to be lifted into a separate function and called via `pthread_create`:

```awk
# spawn { body }  →  emit:
#   1. define a new function  __spawn_N  containing the body
#   2. emit: pthread_create(&tid, NULL, __spawn_N, arg)
if (kind == "id" && val == "spawn") {
    advance()
    spawn_fn = new_spawn_fn_name()
    emit_spawn_fn(spawn_fn, body_tokens)       # emit the lifted function
    emit("  bl _pthread_create_detached_" spawn_fn)
    return
}
```

Alternatively for the short term: run multiple processes with `SO_REUSEPORT` (each process calls `app_listen` independently, kernel load-balances across them). No compiler changes needed:

```sh
# run N workers
for i in 1 2 3 4; do ./server & done
```

Expected speedup: **linear with number of cores** for concurrent workloads.

---

## Issue 3 — `alloc_pages(1)` for every string allocation

### What happens

`alloc_pages(n)` calls `mmap(0, n*4096, PROT_READ|PROT_WRITE, MAP_ANON|MAP_PRIVATE, -1, 0)`. Every small string — URL param keys, flash keys, form field names, query buffers — calls `alloc_pages(1)`, allocating 4096 bytes via a system call for a string that's typically 4–64 bytes.

The compiled server binary has **287 `alloc_pages` call sites**. A single `POST /posts` request hits dozens of them:
- `forge_match_path`: 2 × alloc_pages per URL parameter (key + val)
- `ctx_form`: 1 × alloc_pages per form field for URL-decode buffer
- `ctx_permit`: 1 × alloc_pages per permitted field
- `forge_attrs_insert`: multiple alloc_pages for SQL buffer
- Query buffers: `alloc_pages(1)` for query string, `alloc_pages(512)` for result rows

Each `mmap` syscall costs ~1µs. 50 calls = ~50µs of pure syscall overhead, plus TLB pressure and virtual memory fragmentation.

### Fix — per-request arena allocator

Allocate one large slab at the start of each request; bump-allocate from it; free the whole thing at the end.

```jda
// Arena allocator — one mmap at request start, free at end
struct ForgeArena {
    base: &i8
    pos:  i64
    cap:  i64
}

let g_arena: &ForgeArena = 0

fn forge_arena_init() {
    if g_arena == 0 { g_arena = alloc_pages(1) as &ForgeArena }
    g_arena.base = alloc_pages(32)   // 128KB slab
    g_arena.pos  = 0
    g_arena.cap  = 32 * 4096
}

fn forge_arena_alloc(n: i64) -> &i8 {
    let aligned = (n + 7) and (0 - 8)   // 8-byte align
    if g_arena.pos + aligned > g_arena.cap {
        ret alloc_pages((aligned + 4095) / 4096)   // overflow fallback
    }
    let p = g_arena.base + g_arena.pos
    g_arena.pos = g_arena.pos + aligned
    ret p
}

fn forge_arena_reset() {
    if g_arena != 0 { g_arena.pos = 0 }
}
```

Call `forge_arena_init()` at the start of `forge_handle_fd` and `forge_arena_reset()` at the end. Replace `alloc_pages(1)` in all hot-path functions (`forge_match_path`, `ctx_form`, `ctx_permit`, `forge_attrs_*`, query buffer builders) with `forge_arena_alloc(N)`.

This reduces mmap calls from ~50 per request to 1 at startup.

Expected speedup: **2–5× reduction in syscall overhead.**

---

## Issue 4 — No HTTP keep-alive

### What happens

Every response closes the socket:

```jda
fn forge_handle_fd(fd: i32) {
    ...
    forge_dispatch(app2, &ctx)
    if not ctx.is_ws {
        syscall(FORGE_SYS_CLOSE, fd, ...)   // close after every response
    }
}
```

The browser or load tester must open a new TCP connection for every request: 3-way handshake (~0.5ms loopback, 10–50ms over network).

### Fix — HTTP/1.1 keep-alive loop

Read multiple requests from the same connection until `Connection: close` or timeout:

```jda
fn forge_handle_fd(fd: i32) {
    loop {
        let n = recv(fd, req_buf, max, 0)
        if n <= 0 { break }
        match parse_request(req_buf[0..n]) {
            ok(req) => {
                let ctx = ForgeCtx {}
                ctx.req = req; ctx.fd = fd
                let app: &ForgeApp = g_forge_app
                forge_dispatch(app, &ctx)
                if ctx.is_ws { ret }    // WebSocket owns the fd now
                // Check Connection: close header
                if forge_slice_eq(ctx_header(&ctx, "Connection"), "close") { break }
            }
            err(_) => { break }
        }
    }
    syscall(FORGE_SYS_CLOSE, fd, ...)
}
```

Also add `Connection: keep-alive` to response headers.

Expected speedup: **significant for browser traffic; eliminates TCP handshake per request.**

---

## Issue 5 — `alloc_pages(512)` per query result

### What happens

Every `forge_pg_query` allocates **2MB** for row storage:

```jda
let rows: &i8 = alloc_pages(512)   // 512 × 4096 = 2MB per query
result.rows = rows as &ForgeDbRow
```

This is true even for queries that return 0 rows (session lookups, CSRF checks, existence checks).

### Fix — size to actual row count, or use the arena

Replace `alloc_pages(512)` with a reasonable initial size and grow if needed:

```jda
let rows: &i8 = alloc_pages(4)    // 16KB = ~200 rows initially
```

Or use the arena allocator from Issue 3:

```jda
let rows: &i8 = forge_arena_alloc(FORGE_DB_ROW_STRIDE * 256)
```

Expected speedup: **reduced memory pressure, fewer TLB misses for small result sets.**

---

## Summary

| # | Issue | Per-request cost | Fix complexity | Status |
|---|-------|-----------------|----------------|--------|
| 1 | New DB connection per query | 40–240ms | Low — persistent global fd | ✅ `g_forge_pg_fd` + `forge_pg_get_fd()` |
| 2 | Single-threaded server | 0 concurrency | Medium — compiler `spawn` + pthread | ⏳ Pending — `if pid == 0` inside a loop does not short-circuit in JDA; need compiler fix. Workaround: run `for i in 1 2 3 4; do ./server & done` |
| 3 | mmap per string alloc | ~50µs, memory waste | Medium — arena allocator | ✅ `g_forge_scratch_*` globals + `forge_scratch_alloc/reset`, hot paths replaced |
| 4 | No HTTP keep-alive | TCP overhead per request | Low — loop in forge_handle_fd | ✅ `forge_handle_fd` loops with `forge_hdr_has_close` check |
| 5 | 2MB alloc per query | Memory pressure | Low — reduce alloc_pages(512) | ✅ `alloc_pages(204)` (50 rows), body buffer moved outside loop |

Fix issue 1 first — it will give the biggest single speedup. Fix issues 2 and 4 together to handle concurrent users. Fix issue 3 for memory efficiency and to reduce syscall count.
