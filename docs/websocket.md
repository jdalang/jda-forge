# WebSockets

Forge implements RFC 6455. Each accepted WebSocket connection runs in its own goroutine for the lifetime of the connection.

## Upgrading a connection

Register a GET route and call `forge_ws_upgrade` inside the handler:

```jda
fn handle_ws(ctx: i64) {
    let conn = forge_ws_upgrade(ctx)
    if conn < 0 {
        ctx_bad_request(ctx, "WebSocket upgrade failed")
        ret
    }
    // conn is now a file descriptor for the WebSocket connection
    ws_loop(conn)
}
```

Add the route in `config/routes.jda`:

```
get "/ws" "ws#handle"
```

`forge_ws_upgrade` performs the HTTP → WebSocket handshake and returns an `i32` file descriptor on success, or `-1` on failure.

## Sending and receiving messages

```jda
fn ws_loop(conn: i32) {
    let buf: &i8 = alloc_pages(4)   // 16 KiB receive buffer
    loop {
        let n = forge_ws_recv(conn, buf, 16384)
        if n <= 0 {
            forge_ws_close(conn)
            ret
        }
        let msg = buf[0..n]
        // ... process msg ...
        forge_ws_send_text(conn, "echo: " + msg)
    }
}
```

API summary:

```jda
forge_ws_send_text  (conn, "Hello!")         // send UTF-8 text frame
forge_ws_send_binary(conn, bytes)            // send binary frame
forge_ws_recv(conn, buf, max_bytes) -> i64  // receive next frame; returns 0 when closed
forge_ws_close(conn)                         // send close frame and close fd
```

- `forge_ws_recv` reads one complete frame. Fragmented messages are reassembled internally before being returned.
- `forge_ws_send_text` sends a text frame without masking (server-to-client direction requires no masking per RFC 6455).
- Calling `forge_ws_send_text` or `forge_ws_send_binary` after `forge_ws_close` is a no-op.

## Broadcast pattern

Each connection handler runs in its own goroutine. To broadcast to multiple clients, coordinate through a shared channel or a global connection array.

### Channel-based broadcast

```jda
let g_ws_broadcast_ch: i64 = 0

fn ws_broadcast_init() {
    g_ws_broadcast_ch = chan_new(256)
}

fn ws_broadcaster(arg: i64) {
    loop {
        let msg_ptr = chan_recv(g_ws_broadcast_ch)
        if msg_ptr == 0 { ret }
        let msg = (msg_ptr as &[]i8)[0]
        // Send to all clients — app tracks connections separately
    }
}

fn broadcast(msg: []i8) {
    let mp: &[]i8 = alloc_pages(1) as &[]i8
    mp[0] = msg
    chan_send(g_ws_broadcast_ch, mp as i64)
}
```

### Global connection array (simpler)

For small connection counts, a global array is straightforward:

```jda
let g_ws_conns: [256]i32
let g_ws_conn_count: i64 = 0

fn ws_add_conn(fd: i32) { ... }
fn ws_remove_conn(fd: i32) { ... }

fn ws_broadcast_all(msg: []i8) {
    loop i in 0..g_ws_conn_count {
        forge_ws_send_text(g_ws_conns[i], msg)
    }
}
```

Guard writes to `g_ws_conn_count` with a mutex if connections are added and removed from multiple goroutines concurrently.

## Chat room example

```jda
fn handle_chat(ctx: i64) {
    let conn = forge_ws_upgrade(ctx)
    if conn < 0 { ret }
    ws_add_conn(conn)
    let buf: &i8 = alloc_pages(2)
    loop {
        let n = forge_ws_recv(conn, buf, 8192)
        if n <= 0 {
            ws_remove_conn(conn)
            forge_ws_close(conn)
            ret
        }
        ws_broadcast_all(buf[0..n])
    }
}
```

Add the routes in `config/routes.jda`:

```
get "/chat" "chat#handle"
get "/ws"   "ws#handle"
```

## Protocol notes

- Forge implements RFC 6455.
- Fragmented messages are reassembled internally; `forge_ws_recv` always returns a complete message.
- Server-to-client frames are sent unmasked, as required by the spec.
- Each connection upgrade spawns a goroutine in Forge's connection pool. The handler runs for the lifetime of the connection.

---

# Channels

Channels are a higher-level pub/sub layer built on top of WebSocket — similar to Action Cable in Rails. A channel is a named topic; clients subscribe to it and the server broadcasts to all subscribers.

## Setup

Register channels at startup, before `app_listen`:

```jda
fn main() {
    load_env()
    forge_jobs_start(4)
    forge_migration_run("db/migrate")

    forge_channel_register("posts",
        fn_addr(posts_subscribed),
        fn_addr(posts_received),
        fn_addr(posts_unsubscribed))

    let app = app_new_config(app_config())
    // ... middleware ...
    app_get(app, "/cable", fn_addr(handle_cable))
    app_listen(app, 8080)
}
```

Add the route and handler:

```jda
fn handle_cable(ctx: i64) {
    forge_channel_handle(ctx)   // upgrades WS + runs event loop until disconnect
}
```

`forge_channel_handle` upgrades the connection to WebSocket, reads JSON commands from the client, and dispatches them to the appropriate channel callbacks. It blocks until the client disconnects, then cleans up all subscriptions automatically.

## Callbacks

Each channel has three optional callbacks. All share the same signature `fn my_cb(arg: i64)` where `arg` is a pointer to `ForgeChanCbArg`.

```jda
fn posts_subscribed(packed: i64) {
    let a: &ForgeChanCbArg = packed
    // a.fd = the client's WebSocket fd (i64)
    // send a welcome message back to just this client
    forge_ws_send_text(a.fd as i32, "{\"welcome\":true}")
}

fn posts_received(packed: i64) {
    let a: &ForgeChanCbArg = packed
    let data = (a.data as &i8)[0..a.data_len]
    // data is the "data" field from the client message
    // broadcast it to all subscribers
    forge_channel_broadcast("posts", data)
}

fn posts_unsubscribed(packed: i64) {
    // a.fd just left — cleanup if needed
}
```

`ForgeChanCbArg` fields:

| Field | Type | Description |
|---|---|---|
| `fd` | `i64` | WebSocket file descriptor for this client |
| `data` | `i64` | Pointer to payload bytes (`&i8`), `0` for subscribe/unsubscribe |
| `data_len` | `i64` | Length of `data` |

Pass `0` for any callback you don't need:

```jda
forge_channel_register("notifications", fn_addr(notif_subscribed), 0, 0)
```

## Broadcasting

Broadcast from anywhere — a controller action, a background job, a callback:

```jda
fn post_create(ctx: i64) {
    // ... create the post ...
    forge_channel_broadcast("posts", "{\"event\":\"created\",\"id\":\"42\"}")
    ctx_redirect(ctx, "/posts")
}
```

The message is wrapped in the envelope `{"type":"message","channel":"posts","message":<data>}` before being sent to each subscriber.

## Wire protocol

The channel endpoint speaks a simple JSON protocol over WebSocket:

**Client → Server**
```json
{"command":"subscribe","channel":"posts"}
{"command":"message","channel":"posts","data":"hello"}
{"command":"unsubscribe","channel":"posts"}
```

**Server → Client**
```json
{"type":"confirm_subscription","channel":"posts"}
{"type":"rejection","channel":"posts"}
{"type":"message","channel":"posts","message":"hello"}
```

## Channels API reference

```jda
forge_channel_register(name, on_sub_fn, on_msg_fn, on_unsub_fn)
forge_channel_handle(ctx)                    // route handler — runs event loop
forge_channel_broadcast(name, data)          // fan out to all subscribers
forge_channel_subscribe(name, fd)            // add fd to channel (manual)
forge_channel_unsubscribe(name, fd)          // remove fd from channel (manual)
forge_channel_unsubscribe_fd(fd)             // remove fd from all channels
```

Limits: up to 64 registered channels, 256 subscribers per channel.
