# Overriding Library Behavior (Monkey Patching)

Forge libraries are compiled into your binary via `--include`. Because Jda processes `--include` files before your app source, your app code is always the last definition the compiler sees. This means you can override any library function by redefining it in your own source files — no special syntax needed.

There are three patterns, from safest to most powerful.

---

## Pattern 1 — Wrapper functions (safest)

Wrap a library function without touching it. Call the original inside your version and add your own logic before or after.

```jda
// patches/my_validators.jda

fn my_validate_email(e: &ForgeErrors, field: []i8, val: []i8) -> bool {
    if !forge_validate_format_email(e, field, val) { ret false }
    // extra rule: reject plus-addressing
    loop i in 0..val.len {
        if val[i] == '+' {
            forge_errors_add(e, field, "plus addresses not allowed")
            ret false
        }
    }
    ret true
}
```

Use `my_validate_email` instead of `forge_validate_format_email` in your models. The library function is unchanged; yours layers on top.

---

## Pattern 2 — Patch files (redefine a library function)

Because app source is concatenated and compiled after `--include` files, redefining a function in your app code shadows the library's version. Use a `patches/` directory to keep overrides organised.

**Step 1 — create `patches/`**

```bash
mkdir patches
```

**Step 2 — write a patch**

```jda
// patches/forge_rate_limit.jda
// Override: allow 500 req/min instead of the library default of 100

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

**Step 3 — add `patches/` to your Makefile SRC list**

```makefile
PATCHES = $(wildcard patches/*.jda)
SRC = $(CONFIG) $(MW) $(MODELS) $(VIEWS) $(ROUTES) $(PATCHES) $(MAIN)
```

Patches are concatenated last, so the compiler sees your definition after the library's. The library's version is shadowed.

> **Note:** Only redefine functions you genuinely need to change. Patches couple your app to library internals — a library update may break a patch if the internal logic changes.

---

## Pattern 3 — Middleware override

For HTTP middleware specifically, the simplest override is to not register the library middleware and register your own instead.

```jda
// Don't register forge_cors — use custom CORS
fn my_cors(ctx: i64) {
    let origin = ctx_header(ctx, "Origin")
    // custom origin whitelist logic
    ctx_set_header(ctx, "Access-Control-Allow-Origin", origin)
    ctx_set_header(ctx, "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    ctx_set_header(ctx, "Access-Control-Allow-Credentials", "true")
}

// In main():
// app_use(app, fn_addr(forge_cors))   ← removed
app_use(app, fn_addr(my_cors))         // ← yours
```

For after-the-fact override, register your middleware after the library's — later middleware can overwrite headers set by earlier ones:

```jda
app_use(app, fn_addr(forge_secure_headers))   // sets X-Frame-Options: DENY
app_use(app, fn_addr(my_csp_override))        // overwrites Content-Security-Policy only
```

---

## Pattern 4 — Model callback injection

For the model layer, use the callback system to inject behavior without touching library code:

```jda
// Add your own before_save on top of any library callbacks
forge_callback_add("users", FORGE_CB_BEFORE_SAVE, fn_addr(my_before_save))

fn my_before_save(row_ptr: i64) -> bool {
    // normalize email to lowercase
    ret true
}
```

Callbacks stack — the library's callbacks and yours both run. Return `false` from any callback to abort the operation.

---

## Patch file checklist

When writing a patch, document why it exists so future maintainers understand it:

```jda
// patches/forge_rate_limit.jda
//
// Why: default limit (100 req/min) is too low for our public API.
//      Raised to 500. Revisit if we add Redis-backed rate limiting.
// Overrides: forge_rate_limit in forge.jda
// Tested by: test/test_rate_limit.jda
```

---

## Keeping patches maintainable

| Do | Avoid |
|---|---|
| Keep one function per patch file | Patching many functions in one file |
| Name patch files after the function: `forge_rate_limit.jda` | Generic names like `overrides.jda` |
| Write a test that exercises the patch | Assuming the patch works silently |
| Note which library version the patch was written against | Leaving version context unstated |
| Remove patches when the library itself is updated with the fix | Accumulating stale patches |
