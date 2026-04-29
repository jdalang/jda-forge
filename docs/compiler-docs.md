# JDA Compiler & Runtime Documentation

This document tracks known bugs and ARM64 code-generation quirks in the JDA compiler (`~/.jda/bin/jda`) discovered during development of the Forge runtime. For each issue: what it is, where it lives, what it breaks, the runtime workaround applied in `forge.jda`, and the proper compiler fix.

---

## Bug 1 — Sub-slice `s[a..b]` discards end index, making `.len` wrong

### What happens

In `arm64_parse_postfix` (around line 800), the `[start..end]` slice operator emits:

```awk
emit("  mov x10, x0")         # save start offset
if (peek_kind() != "]") arm64_parse_expr()  # parse end — result in x0, immediately discarded
emit("  ldr x0, [sp], #16")  # restore base pointer
emit("  add x0, x0, x10")    # return base + start
```

The `end` value is parsed and then thrown away. The returned pointer is `base + start` with no length attached. Because `.len` calls `strlen`, the length of a sub-slice equals the `strlen` of the original string from position `start` onward — not `end - start`.

### What breaks

Any code that compares or uses the length of a sub-slice gets the wrong answer. Concretely:

| Call site | Expected | Actual |
|-----------|----------|--------|
| `forge_slice_eq(s[0..4], "post")` | compare 4 chars | compare `strlen(s)` chars → always false |
| `ctx_flash_get` comparing flash kind | match "alert" (5) | strlen of full flash string |
| `forge__singularize` returning `res[0..n-1]` | "post" (length 4) | "posts" (length 5) |
| `forge_match_path` storing `pattern[ps+1..pi]` as param key | "post_id" | full pattern tail |

### Runtime workarounds applied

Because fixing the compiler takes time, the following call sites in `forge.jda` were rewritten to avoid sub-slice `.len` comparisons:

- **`forge__singularize`** — now copies into a fresh `alloc_pages(1)` buffer and null-terminates at `n-1`.
- **`forge_match_path`** — URL param keys and values are now copied into fresh null-terminated buffers instead of returned as sub-slices.
- **`forge__ctrl_from_str`** — copies controller name into a fresh buffer instead of returning `s[0..i]`.
- **`ctx_flash_get`** — compares flash kind character-by-character up to `sep` instead of `forge_slice_eq(raw[0..sep], kind)`.

### Compiler fix

The slice operator must track `end - start` as the effective length. Two approaches:

**Option A — Null-terminate at end position (simplest, only correct for `[]i8`):**
```awk
# After parsing start and end:
emit("  mov x10, x0")              # start in x10
arm64_parse_expr()                  # end in x0
emit("  ldr x9, [sp], #16")        # restore base
emit("  add x0, x9, x0")           # base + end → null terminator position
emit("  strb wzr, [x0]")           # write \0 at base+end
emit("  add x0, x9, x10")          # return base + start
```

This makes `base[start..end]` a properly null-terminated string. The byte at `base[end]` is set to `\0` in-place, so `strlen` returns `end - start`. This assumes the buffer is writable and has room for the null byte — both true for heap-allocated strings in Forge.

**Option B — Fat pointer `(ptr, len)` pair** — requires ABI changes (two-register return). Too invasive for now; Option A is sufficient for `[]i8`.

---

## Bug 2 — `let x: [N]type` without `=` steals the next statement

### What happens

In `arm64_gen_stmt`, the `let` statement parser at line ~1115:

```awk
if (peek_kind() == ":") {
    advance()
    if (peek_kind() == "&") advance()   # skip &TypeName prefix
    if (peek_kind() == "id") { var_type[name] = peek_val(); _has_type_ann = 1 }
    while (peek_kind() != "=" && peek_kind() != "eof") advance()
}
expect("=")
```

When `let x: [32]i8` is written **without `=`**, the parser:
1. Sees `:`, advances.
2. Sees `[`, which is NOT `id` — so `_has_type_ann` stays 0 and the type is not stored.
3. `while (peek_kind() != "=")` — scans forward consuming tokens until it hits `=`. This eats the **next statement** if it starts with `=`, such as `let tpos = 0i64`.
4. The next statement's name becomes part of the current variable's type, and `tpos` is never declared.

Result: the compiler sets `var_type["x"] = "i64"` (the type of the stolen statement's value) and allocates an `i64` slot instead of a 32-byte array. Any array element write then computes address `0 + index * 8` and crashes.

### What breaks

Any fixed-array local declared with type annotation and no initializer:

```jda
let tmp: [32]i8      // BUG — steals next statement
let tpos = 0i64      // this line is eaten

// vs correct form:
let tmp = [32]i8     // OK — parsed as array initializer
let tpos = 0i64      // this line is parsed normally
```

Affected in `forge.jda` before the fix:
- `i64_to_str` — `let tmp: [32]i8` crashed with SIGSEGV on the first write to `tmp[0]`
- HTML escaping — `let ch: [1]i8` had the same issue

### Runtime workaround applied

All `let x: [N]type` declarations were changed to `let x = [N]type` form throughout `forge.jda`.

### Compiler fix

The type annotation parser must handle array types. After advancing past `:`:

```awk
if (peek_kind() == ":") {
    advance()
    if (peek_kind() == "&") advance()          # skip & prefix
    if (peek_kind() == "[") {                  # [N]type or []type
        advance()                               # consume [
        if (peek_kind() != "]") {
            # skip N or constant
            while (peek_kind() != "]" && peek_kind() != "eof") advance()
        }
        advance()                               # consume ]
    }
    if (peek_kind() == "id") { var_type[name] = peek_val(); _has_type_ann = 1 }
    while (peek_kind() != "=" && peek_kind() != "eof") advance()
}
```

But ideally the `let x: [N]type` form without `=` should also allocate the array on the stack and zero it, just like `let x = [N]type`. The two forms should be identical:

```awk
# After parsing "let name" and seeing ":"
# Detect [N]type annotation and treat it as an array init
if (peek_kind() == "[") {
    # parse the N
    # allocate N bytes on the stack
    # zero-initialize
    # bind env[name] to stack slot base address
    _has_type_ann = 1
    # do NOT expect("=") — the = is optional for array declarations
}
```

---

## Bug 3 — Missing UFCS shims for query builder methods

### What happens

The JDA method-call syntax `obj.method(args)` in expression position (inside `arm64_parse_postfix`, line ~760) emits:

```awk
if (saved_lt != "") {
    emit("  bl _" saved_lt "__" fname_f)
} else {
    emit("  bl _" fname_f)
}
```

After any function call `LAST_TYPE = ""`, so every chained method call falls into the `else` branch and emits `bl _method_name` (no type prefix). This means `.where_not_deleted()` emits `bl _where_not_deleted` — a free function that must exist.

For the query builder, short-name shim functions are defined in `forge.jda`:
```jda
fn where_eq(q: &ForgeQuery, col: []i8, val: []i8) -> &ForgeQuery { ret forge_q_where_eq(q, col, val) }
fn order_asc(q: &ForgeQuery, col: []i8) -> &ForgeQuery { ret forge_q_order_asc(q, col) }
// etc.
```

Several were missing, causing silent linker errors (`ld: symbol(s) not found`) and the method call being a no-op.

### Runtime workaround applied

Added the missing shims to `forge.jda`: `where_not_deleted`, `with_deleted`, `only_deleted`, `where_raw`, `where_not`, `limit`, `offset`.

### Compiler fix

The compiler should preserve the receiver type across chained calls. After a function call, the return type should be inferred from a function signature table built during the prescan pass. Specifically:

1. During prescan, record `fn_return_type[fname]` for all functions.
2. In `arm64_parse_postfix`, after emitting `bl _fname`, set:
   ```awk
   LAST_TYPE = (name in fn_return_type) ? fn_return_type[name] : ""
   ```
3. For chained calls, use `saved_lt` (the receiver's type) to build the qualified name:
   ```awk
   emit("  bl _" saved_lt "__" fname_f)
   ```

This would make `.where_not_deleted()` on a `&ForgeQuery` receiver emit `bl _ForgeQuery__where_not_deleted` (or the appropriate qualified name), without needing shim functions.

---

## Bug 4 — `if cond { loop { ... } }` falls through in forked child

### What happens

When a forked child process executes:
```jda
let pid = syscall(2, 0,0,0,0,0,0) as i32   // fork()
if pid == 0 {
    loop {
        let cfd = syscall(30, lfd, sa, salen, 0,0,0) as i32
        if cfd >= 0 { forge_handle_fd(cfd) }
    }
}
// expected: child stays above; parent continues here
```

The child does not stay trapped in the inner `loop { }`. Instead it exits the `if` block and continues executing code after it — including the outer loop body — causing an exponential fork cascade (2^N processes for N fork iterations).

### What breaks

Any pre-fork worker model that uses `if pid == 0 { loop { ... } }` to keep children in a service loop. With N=3 fork iterations, 8 processes are created and all reach the code after the if block.

### Suspected cause

The `arm64_gen_stmt` for `if` may not correctly handle an inner infinite `loop { }` as a terminator — it may fall through after generating the loop body's branch back, without recognizing that no code path exits. The branch target at the end of the `if` block then gets executed unconditionally.

### Workaround applied

Pre-fork removed from `app_listen`. Users wanting multi-process concurrency should launch multiple server instances with the shell:
```sh
for i in 1 2 3 4; do APP_PORT=8080 ./server & done
```
Each process binds independently (with `SO_REUSEADDR` already set), but only one will succeed on macOS without `SO_REUSEPORT`. A proper fix requires either the compiler fix above or adding `SO_REUSEPORT` to `TcpListener__bind` and launching processes independently.

### Compiler fix

After generating the body of `if cond { ... }`, the compiler should check whether the last statement in the body is a `loop { }` (no break) — a provably non-terminating statement. If so, it should not emit a branch past the if block's closing label for the true branch.

---

## Bug 5 — Function call clears `LAST_TYPE`, causing wrong struct field offsets when result is untyped

### What happens

In `arm64_parse_postfix` (lines ~725, ~764), every function call ends with:

```awk
LAST_TYPE = ""
```

The compiler never records function return types, so after any call `x = f(...)`, `LAST_TYPE` is empty. When a subsequent field access like `.author` is compiled, `find_field_off("author", "")` is called with an empty type hint and falls back to iterating over **all structs** in arbitrary AWK hash order. The first struct that contains the field wins — which may not be the correct one.

Concretely, with two models declared:

```jda
struct PostRow    { id, title, body, author, ...  }   // author at offset 24
struct CommentRow { id, post_id, author, body, ... }   // author at offset 16
```

`find_field_off("author", "")` returns **16** (CommentRow wins the hash lottery) when the variable actually holds a `&PostRow`. The generated load is `ldr x0, [x0, #16]` — which reads `PostRow.body` instead of `PostRow.author`.

### What breaks

Any variable bound to a function call result **without an explicit type annotation**, whose type is one of multiple structs sharing the same field name:

```jda
let p = post_row(post, 0)   // p has no type — LAST_TYPE="" after the call
p.author                    // compiled as p[16] (CommentRow offset) instead of p[24]
p.created_at                // compiled as p[32] instead of p[40]
```

Fields that are unique across all structs (e.g. `title`, `post_id`) are unaffected because `find_field_off` finds only one match and returns the right offset regardless of order.

### Runtime workaround applied

Add an explicit type annotation on any `let` that binds a struct-returning function call:

```jda
// Before (broken when multiple structs share the field name):
let p = post_row(post, 0)

// After (correct):
let p: &PostRow = post_row(post, 0)
```

The let-parser already handles the `&TypeName` annotation (it skips `&` at line ~1117 before reading the type identifier), so no compiler change is needed for the workaround.

Applied in `examples/blog/app/views/posts/show.html.jda` and `edit.html.jda`.

### Compiler fix

During the prescan pass (where structs and consts are collected), also record function return types:

```awk
} else if (peek_kind() == "kw" && peek_val() == "fn") {
    advance()
    fname = peek_val(); advance()          # function name
    # ... skip parameter list ...
    if (peek_kind() == "-" && tk_val[POS+1] == ">") {
        advance(); advance()               # consume ->
        if (peek_kind() == "&") advance()  # skip &
        if (peek_kind() == "id") fn_return_type[fname] = peek_val()
    }
}
```

Then in `arm64_parse_postfix`, after every `bl _fname`, set:

```awk
LAST_TYPE = (fname in fn_return_type) ? fn_return_type[fname] : ""
```

This also fixes Bug 3's need for UFCS shims, since the receiver type would be correctly preserved across chained calls.

---

## Bug 6 — Embedded array field slice reads slot as pointer, not inline data

### What happens

In JDA ARM64 structs, an array field declared as `[N]i8` is stored **inline** — its bytes start at the field's offset. However, when you write `struct.array[0..n]` (a slice expression on a struct field), the compiler:

1. Loads the 8 bytes at the field's offset into a register — interpreting those 8 bytes as a **pointer**.
2. Applies the slice from that pointer value.

Because the inline bytes are raw character data (not a heap address), the result is a nonsense pointer → crash on any dereference.

The same problem applies to field accesses like `row.cols` where `cols` is a `[N]SomeStruct` array declared inline at offset 0: the compiler reads 8 bytes and treats them as a pointer.

### What breaks

Any code that reads an embedded array field with a slice expression:

```jda
struct ForgeDbRow {
    cols: [FORGE_DB_MAX_COLS]ForgeDbCell   // inline at offset 0
    count: i64
}

let row: &ForgeDbRow = ...
let cell = row.cols[2]          // BUG — reads 8 bytes at offset 0 as pointer
let slice = row.cols[0..n]      // BUG — same
```

Broken patterns in `forge.jda` before the fix:
- `row.cols as i64 + c * FORGE_DB_COL_STRIDE` — `row.cols` read the 8 inline bytes as an address → always 0 for a zero-initialized alloc → SIGSEGV
- `cell.data[0..cell.len]` in `forge_row_col` — `cell.data` treated as pointer → crashed in `forge_sql_write`
- `e.child[0..e.clen]` in `forge__cc_after_create` — same

### Runtime workaround applied

Cast the struct pointer to `&i8` first, then slice from the raw address:

```jda
// Before (broken):
let slice = row.cols[0..n]
let addr  = row.cols as i64 + n * STRIDE

// After (correct):
let base: &i8 = (row as i64) as &i8     // cols is at offset 0
let slice = base[0..n]
let addr  = (row as i64) + n * STRIDE
```

For a field at a non-zero offset, add the offset explicitly:

```jda
// fk_col is at offset 16 in ForgeCounterCacheEntry:
let efk: &i8 = (e as i64 + 16) as &i8
let fk_slice = efk[0..e.flen]
```

Applied in:
- `forge_db_query` D-branch: `row as i64` instead of `row.cols as i64`
- `forge_row_col`: `(cell as i64) as &i8` then `cptr[0..cell.len]`
- `forge__cc_after_create`: `(e as i64) as &i8` for child and `(e as i64 + 16) as &i8` for fk_col

### Compiler fix

The code generator for `struct.field_name` on an embedded-array field must emit the **address** of the field slot, not a load from it. When the field type is `[N]T` (a fixed-size inline array), the postfix pass should:

1. Compute `base + field_offset` as the result (no load).
2. Leave `LAST_TYPE = "array"` (or the element type) so a subsequent `[i]` subscript emits `base + field_offset + i * sizeof(T)`.
3. For a slice `[a..b]`, emit `base + field_offset + a` with length `b - a` (once fat pointer/null-terminator is in place).

Currently the same `ldr x0, [x0, #offset]` is emitted for both pointer fields and inline-array fields, which is correct only for pointers.

---

## Bug 7 — `bl` overwrites `lr` (x30); functions without prologue corrupt callers' return address

### What happens

On ARM64, the `bl` (branch-with-link) instruction writes the return address into `x30` (the link register). JDA emits a function prologue (`stp x29, x30, [sp, #-16]!`) only for functions that need a stack frame (i.e., those with local variables that spill). Functions with few or no locals get no prologue/epilog.

When a callee with no prologue calls further functions via `bl`, `x30` is overwritten. On return (`ret`), the processor uses the current (corrupted) `x30` — jumping to wherever the last `bl` pointed, not back to the original caller.

### What breaks

Any function that:
1. Has few enough locals that JDA doesnits not emit `stp x29, x30, [sp, #-16]!`, AND
2. Calls another function via `bl` before its own `ret`.

Examples hit during Forge development:

| Function | Symptom | Root cause |
|----------|---------|------------|
| `forge__cc_after_create` | Infinite loop / crash after checking `g_forge_cc_count` | `bl forge_cc_init` clobbered `lr`; `ret` jumped back into the loop |
| `forge_instrument` | Infinite loop after `[FI2]` debug print | `bl forge_instr_init` clobbered `lr`; `if _ic == 0 { ret }` returned to wrong address |
| `post_after_create` | Crash at `call_fn` | `bl forge_instrument` clobbered `lr`; `ret true` jumped to garbage |

### Runtime workaround applied

Restructure the function so the first thing checked is a global flag — **before** any `bl` instruction. If the guard condition is false, `ret` early while `lr` is still valid:

```jda
// Before (broken — bl overwrites lr before the check):
fn forge_instrument(event: []i8, payload: i64) {
    forge_instr_init()           // bl clobbers x30
    let _ic = g_forge_instr_count
    if _ic == 0 { ret }          // ret uses corrupted x30
    ...
}

// After (correct — ret fires before any bl):
fn forge_instrument(event: []i8, payload: i64) {
    if g_forge_instr_count == 0 { ret }   // pure register check, no bl
    forge_instr_init()
    ...
}
```

Applied in:
- `forge__cc_after_create`: `if g_forge_cc_count == 0 { ret }` before `forge_cc_init()`
- `forge_instrument`: `if g_forge_instr_count == 0 { ret }` before `forge_instr_init()`
- `post_after_create` (blog example): `if g_forge_instr_count > 0 { forge_instrument(...) }` so `bl` is never reached when count is 0

### Compiler fix

Every function that contains a `bl` instruction must save and restore `lr`. The prologue/epilog should be emitted unconditionally for any function that calls another, regardless of local variable count:

```awk
# In arm64_gen_fn, always emit prologue when function body contains any bl:
emit("  stp x29, x30, [sp, #-16]!")
emit("  mov x29, sp")
# ... body ...
emit("  ldp x29, x30, [sp], #16")
emit("  ret")
```

A simpler rule: emit prologue/epilog for every non-leaf function (any function that contains a `bl`). The performance cost is two extra memory operations per call, which is negligible.

---

## Summary

| # | Bug | Severity | Status |
|---|-----|----------|--------|
| 1 | `s[a..b]` discards `end`, `.len` calls strlen of full string | Critical | Worked around in forge.jda |
| 2 | `let x: [N]type` without `=` steals next statement | Critical | Worked around (use `=` form) |
| 3 | Missing UFCS shims cause linker errors for unknown method names | Medium | Worked around in forge.jda |
| 4 | `if cond { loop { ... } }` does not trap child in loop — all code paths fall through | High | Blocks pre-fork worker model; workaround: run multiple server processes manually |
| 5 | Function call clears `LAST_TYPE` — untyped call results get wrong struct field offsets | High | Worked around with explicit type annotations |
| 6 | Embedded array field slice/load reads slot as pointer, not inline data | Critical | **Fixed in forge.jda** — use `(struct as i64) as &i8` pattern |
| 7 | `bl` clobbers `lr`; functions without prologue/epilog corrupt return address | Critical | **Fixed in forge.jda** — guard with global flag check before any `bl` |

Bugs 1–5 have runtime workarounds in place. Bugs 6–7 are fully fixed in forge.jda with the patterns documented above. The compiler fixes are the proper long-term solution for all seven.
