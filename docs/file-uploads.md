# File Uploads

## ForgeUpload struct

```jda
struct ForgeUpload {
    field_name:   []i8   // HTML form field name
    filename:     []i8   // original filename from the browser
    content_type: []i8   // e.g. "image/jpeg"
    data:         []i8   // raw file bytes
    size:         i64    // byte count
}
```

## Parsing a multipart upload

The HTML form must use `enctype="multipart/form-data"`:

```html
<form action="/avatars" method="POST" enctype="multipart/form-data">
    <input type="file" name="avatar">
    <input type="submit" value="Upload">
</form>
```

In the handler, call `forge_multipart_parse` with the context, the field name, and a pointer to a `ForgeUpload`:

```jda
fn handle_avatar_upload(ctx: i64) {
    let upload: ForgeUpload
    let ok = forge_multipart_parse(ctx, "avatar", &upload)
    if !ok {
        ctx_bad_request(ctx, "No file uploaded")
        ret
    }
    // upload.filename, upload.content_type, upload.data, upload.size are now populated
    let saved_path = forge_upload_save(&upload, "public/uploads/avatars")
    if saved_path.len == 0 {
        ctx_bad_request(ctx, "Could not save file")
        ret
    }
    // saved_path = "public/uploads/avatars/<uuid>.<ext>"
    ctx_redirect(ctx, "/profile")
}
```

## Saving an upload

```jda
let path = forge_upload_save(&upload, "public/uploads")
// Returns the saved path (e.g. "public/uploads/a3f8...jpeg")
// Returns "" on failure
```

`forge_upload_save` behavior:

- Generates a UUID-based filename to prevent collisions and path traversal
- Preserves the original file extension (lowercased)
- Creates the target directory if it does not exist
- Returns the saved path relative to the project root

## Validating uploads

Validate size and content-type before saving. Use `ForgeErrors` to collect validation failures and redirect back if any are present:

```jda
fn validate_upload(upload: &ForgeUpload, errs: &ForgeErrors) {
    // Size limit (5 MB)
    if upload.size > 5 * 1024 * 1024 {
        forge_errors_add(errs, "avatar", "must be under 5 MB")
    }
    // Content-type whitelist
    let ct = upload.content_type
    let allowed = false
    if forge_slice_eq(ct, "image/jpeg") or
       forge_slice_eq(ct, "image/png")  or
       forge_slice_eq(ct, "image/gif")  { allowed = true }
    if !allowed {
        forge_errors_add(errs, "avatar", "must be a JPEG, PNG, or GIF")
    }
}

fn handle_avatar_upload(ctx: i64) {
    let upload: ForgeUpload
    let ok = forge_multipart_parse(ctx, "avatar", &upload)
    if !ok { ctx_bad_request(ctx, "No file")  ret }

    let errs = forge_errors_new()
    validate_upload(&upload, errs)
    if forge_errors_any(errs) {
        ctx_flash_set(ctx, "alert", forge_errors_json(errs))
        ctx_redirect(ctx, "/profile/edit")
        ret
    }

    let path = forge_upload_save(&upload, "public/uploads/avatars")
    // ... save path to database ...
    ctx_redirect(ctx, "/profile")
}
```

## Serving uploaded files

Uploaded files saved to `public/uploads/` can be served as static files:

```jda
forge_static(app, "/uploads", "public/uploads")
```

A file saved to `public/uploads/avatars/abc123.jpg` is then accessible at `/uploads/avatars/abc123.jpg`.

## Multiple file uploads

Parse each field individually:

```jda
let photo1: ForgeUpload
let photo2: ForgeUpload
forge_multipart_parse(ctx, "photo1", &photo1)
forge_multipart_parse(ctx, "photo2", &photo2)
```

## Security considerations

- `forge_upload_save` generates a random UUID filename and does NOT use the original filename, preventing path traversal.
- Always validate content-type and size before saving.
- Content-type is reported by the browser and can be spoofed. For high-security use cases, inspect the first few bytes of `upload.data` to verify the file signature (magic bytes).
- Never save uploads inside the source tree (`models/`, `routes/`, etc.).
- Set appropriate permissions on the upload directory.
