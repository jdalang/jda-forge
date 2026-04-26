# JDA Compiler Bugs

This document tracks known bugs in the JDA compiler (`~/.jda/bin/jda`) discovered during development of the Forge runtime. For each bug: what it is, where it lives, what it breaks, and what the fix looks like.

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

## Summary

| # | Bug | Severity | Status |
|---|-----|----------|--------|
| 1 | `s[a..b]` discards `end`, `.len` calls strlen of full string | Critical | Worked around in forge.jda |
| 2 | `let x: [N]type` without `=` steals next statement | Critical | Worked around (use `=` form) |
| 3 | Missing UFCS shims cause linker errors for unknown method names | Medium | Worked around in forge.jda |

All three bugs have runtime workarounds already in place. The compiler fixes are the proper long-term solution.
