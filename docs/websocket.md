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
