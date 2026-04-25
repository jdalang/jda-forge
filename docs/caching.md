# Caching

Forge includes an in-process, TTL-based key/value cache backed by a fixed-size array. It requires no external infrastructure and has no network round-trip overhead.

Trade-offs to be aware of:

- The cache is not shared across multiple server processes.
- It does not survive restarts.
- The default store is capped at `FORGE_CACHE_MAX` entries (default: 512).

For multi-process or persistent caching, use PostgreSQL directly, or treat `forge_cache_set` as a write-through layer backed by your DB.

## Basic operations

```jda
// Store a value for 300 seconds
forge_cache_set("my_key", "my_value", 300)

// Retrieve — returns "" if missing or expired
let val = forge_cache_get("my_key")
if val.len == 0 { /* cache miss */ }

// Check existence without retrieving
let hit: bool = forge_cache_has("my_key")

// Delete a specific key
forge_cache_del("my_key")

// Flush everything
forge_cache_clear()
```

## TTL rules

- `ttl_sec > 0` — entry expires after `ttl_sec` seconds.
- `ttl_sec == 0` — entry never expires. Use sparingly; the store is fixed-size.
- Expired entries are evicted lazily on the next read of that key. No background sweep runs.

## Cache middleware

`forge_cache_middleware` caches full HTTP responses. Register it after logging middleware, before your route handlers:

```jda
app_use(app, fn_addr(forge_logger))
app_use(app, fn_addr(forge_cache_middleware))
// ... routes ...
```

Middleware behaviour:

- Only caches GET requests.
- Cache key: request path + query string.
- Default TTL: 60 seconds.
- Bypass: set `Cache-Control: no-store` on the response to skip caching for that request.

```jda
// Change the middleware TTL globally
forge_cache_middleware_ttl(300)   // 5 minutes

// In a handler: bypass response caching for this specific request
ctx_set_header(ctx, "Cache-Control", "no-store")
```

## Cache-aside pattern

Check the cache first, query the database on a miss, then store the result:

```jda
fn get_homepage_data() -> []i8 {
    let cached = forge_cache_get("homepage_posts")
    if cached.len > 0 { ret cached }

    // Cache miss — build from database
    let posts = forge_q("posts")
        .where_eq("status", "published")
        .order_desc("created_at")
        .limit(10)
        .exec()
    let json = forge_result_to_json(posts)
    forge_cache_set("homepage_posts", json, 120)   // cache for 2 minutes
    ret json
}
```

## Cache invalidation

Delete affected keys when the underlying data changes. Do this in the controller action after calling the auto-generated update function:

```jda
fn posts_update(ctx: i64) {
    let id    = ctx_param(ctx, "id")
    let title = ctx_param(ctx, "title")
    let body  = ctx_param(ctx, "body")
    let ok = post_update(id, title, body)   // auto-generated from migration
    if ok {
        forge_cache_del("homepage_posts")
        forge_cache_del("post_" + id)
    }
    ctx_redirect(ctx, post_path(id))
}
```

Invalidate as specifically as possible. Calling `forge_cache_clear()` flushes everything, which can cause a burst of DB queries if many keys are cold at once.

## Rate limiting with cache

The cache works well for lightweight rate limiting within a single process:

```jda
fn check_rate_limit(ip: []i8, limit: i64, window_sec: i64) -> bool {
    let key   = "rl:" + ip
    let val   = forge_cache_get(key)
    let count = str_to_i64(val)
    if count >= limit { ret false }
    forge_cache_set(key, i64_to_str(count + 1), window_sec)
    ret true
}

fn my_login_handler(ctx: i64) {
    if !check_rate_limit(ctx_ip(ctx), 5, 60) {
        ctx_too_many_requests(ctx)
        ret
    }
    // ... process login ...
}
```

Note: because the cache is per-process, this limit applies per server instance. For a distributed rate limit, write counts to PostgreSQL.

## Cache capacity and eviction

The default store holds up to `FORGE_CACHE_MAX` entries (default: 512). When the store is full:

1. Expired entries are evicted first.
2. If no expired entries exist, the oldest entry is replaced.

For workloads that need more than 512 live entries, either increase `FORGE_CACHE_MAX` at compile time or move to PostgreSQL or an external Redis server.
