# Server-Sent Events (SSE)

## What is SSE?

Server-Sent Events is a simple HTTP protocol for pushing real-time updates from server to browser. The browser opens one long-lived connection and receives a stream of `data:` messages. Unlike WebSocket, SSE is one-directional (server to client) and works over plain HTTP/1.1.

Good use cases: live dashboards, notifications, activity feeds, progress bars.

## Handler setup

```jda
fn handle_events(ctx: i64) {
    forge_sse_start(ctx)   // sets Content-Type: text/event-stream, disables buffering

    let i = 0
    loop {
        // Send an event with a named type and data payload
        forge_sse_send(ctx, "update", "{\"count\":" + i64_to_str(i) + "}")
        i = i + 1
        forge_sleep_ms(1000)   // send every second
    }
}
```

Add the route in `config/routes.jda`:

```
get "/events" "events#handle"
```

## forge_sse_start

Must be called before any other SSE function. It sets the following headers and flushes them immediately:

- `Content-Type: text/event-stream`
- `Cache-Control: no-cache`
- `Connection: keep-alive`

## Sending events

```jda
forge_sse_send(ctx, "message", "Hello!")
// Sends:  event: message\ndata: Hello!\n\n

forge_sse_send(ctx, "update",  "{\"users\":42}")
// Sends:  event: update\ndata: {"users":42}\n\n

forge_sse_ping(ctx)
// Sends: : ping\n\n  (keeps the connection alive through proxies)
```

## Closing the stream

```jda
forge_sse_close(ctx)
// Sends: event: close\ndata: \n\n  and signals client to close
```

Alternatively, return from the handler — Forge closes the connection when the handler function returns.

## Client-side JavaScript

```javascript
const es = new EventSource('/events');

es.addEventListener('update', (e) => {
    const data = JSON.parse(e.data);
    document.getElementById('count').textContent = data.count;
});

es.addEventListener('message', (e) => {
    console.log(e.data);
});

es.onerror = () => {
    // Browser auto-reconnects after a few seconds
};
```

## Live notification feed example

```jda
fn handle_notifications(ctx: i64) {
    let user_id = ctx_session_get(ctx, "user_id")
    if user_id.len == 0 {
        ctx_unauthorized(ctx)
        ret
    }

    forge_sse_start(ctx)

    loop {
        // Poll for new notifications every 3 seconds
        let notifs = forge_q("notifications")
            .where_eq("user_id", user_id)
            .where_eq("seen", "false")
            .order_desc("created_at")
            .limit(5)
            .exec()

        if notifs.count > 0 {
            let json = forge_result_to_json(notifs)
            forge_sse_send(ctx, "notification", json)
            // Mark as seen
            forge_q("notifications").where_eq("user_id", user_id).update_all("seen = true")
        } else {
            forge_sse_ping(ctx)
        }

        forge_sleep_ms(3000)
    }
}
```

## SSE vs WebSocket

| | SSE | WebSocket |
|---|---|---|
| Direction | Server to client only | Bidirectional |
| Protocol | Plain HTTP | Separate WS protocol |
| Auto-reconnect | Yes (browser handles it) | No (app must reconnect) |
| Good for | Feeds, notifications, progress | Chat, games, collaborative editing |
| Firewall/proxy friendly | Yes | Sometimes requires proxy config |

## Keepalive pings

Some proxies and load balancers close idle connections after 30–60 seconds. Send a ping periodically to keep the connection alive:

```jda
loop {
    // ... check for events ...
    forge_sse_ping(ctx)
    forge_sleep_ms(20000)   // ping every 20 seconds
}
```

## API reference

| Function | Description |
|---|---|
| `forge_sse_start(ctx)` | Initialize SSE response headers |
| `forge_sse_send(ctx, event, data)` | Send a named event |
| `forge_sse_ping(ctx)` | Send a keepalive comment |
| `forge_sse_close(ctx)` | Send close event |
