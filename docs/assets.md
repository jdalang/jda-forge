# Asset Pipeline

Forge ships a Rails-style asset pipeline: CSS and JS files are fingerprinted in production so browsers cache them forever, and stale assets are busted automatically on deploy.

---

## Directory layout

```
app/assets/
  stylesheets/
    application.css        # compiled as a standalone asset
    _variables.css         # _ prefix → partial, not compiled standalone
  javascripts/
    application.js
    _utils.js              # partial, not compiled standalone
  images/
    logo.png               # copied as-is, no fingerprinting
public/assets/             # output directory (gitignore this)
_build/assets.jda          # generated code — do not edit
```

Files starting with `_` are treated as partials and are **not** compiled as independent assets. Reference them via `@import` (CSS) or by concatenating them manually.

---

## Helper functions

After `forge compile-assets` runs, `_build/assets.jda` provides four functions:

```jda
forge_asset_path("application.css")
// dev:  "/assets/application.css"
// prod: "/assets/application-abc123def4567890.css"

forge_stylesheet_tag("application.css")
// → <link rel="stylesheet" href="/assets/application-abc123def4567890.css">

forge_javascript_tag("application.js")
// → <script src="/assets/application-xyz789abc0123456.js"></script>

forge_image_tag("logo.png", "Site logo")
// → <img src="/assets/logo.png" alt="Site logo">
```

Use these in view functions and layouts — never hard-code asset paths.

---

## Usage in a layout

```jda
fn tmpl_layout(title: []i8, body: []i8) -> []i8 {
    let buf = forge_buf_new(4)
    buf.write("<!DOCTYPE html><html><head><meta charset=utf-8>")
    buf.write("<title>")  buf.write(title)  buf.write("</title>")
    buf.write(forge_stylesheet_tag("application.css"))
    buf.write("</head><body>")
    buf.write(body)
    buf.write(forge_javascript_tag("application.js"))
    buf.write("</body></html>")
    ret buf.done()
}
```

---

## Development vs production

| Mode | Fingerprinting | Source copied to `public/assets/`? |
|---|---|---|
| development (default) | No | Yes (original filename) |
| production | Yes (SHA-256, 16 chars) | Yes (fingerprinted filename) |

In development the files are always up to date — no browser cache busting needed. In production the fingerprinted filename changes whenever the file content changes, so you can set a far-future `Cache-Control: max-age` on `/assets/*`.

---

## CLI commands

```bash
forge compile-assets                   # dev (no fingerprint)
forge assets:precompile                # production (fingerprinted)
forge assets:precompile --environment staging
```

`forge build` and `forge server` call `compile-assets` automatically. `forge assets:precompile` is for CI/deploy pipelines.

---

## Build pipeline integration

The generated Makefile includes assets in the build:

```makefile
ASSETS_GEN = _build/assets.jda

SRC = $(CONFIG) $(HELPERS) $(MODELS_GEN) $(ASSETS_GEN) $(MODELS) $(VIEWS) \
      $(CONTROLLERS) $(CTRL_INIT) $(ROUTES) $(MAIN)

_gen:
    @forge compile-routes
    @forge compile-models
    @forge compile-assets
```

`ASSETS_GEN` must come before models and views in `SRC` so view functions can call `forge_stylesheet_tag` / `forge_javascript_tag` without forward-reference errors.

---

## Serving assets

`forge server` mounts `public/` as a static file root. Requests to `/assets/application-abc123.css` are served directly from `public/assets/`.

In production, put a CDN or reverse proxy in front and point it at `public/assets/`. Set `Cache-Control: public, max-age=31536000, immutable` on all fingerprinted files — the filename hash guarantees cache safety.

---

## Gitignore

Add `public/assets/` to `.gitignore` and check in only the source files under `app/assets/`. Generate `public/assets/` and `_build/assets.jda` as part of the deploy/build step.

```
# .gitignore
public/assets/
_build/
```
