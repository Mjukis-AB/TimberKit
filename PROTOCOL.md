# TimberKit Wire Protocol Specification

Version: 1.0

## Overview

TimberKit uses a simple JSON-based protocol over TCP. Messages are newline-delimited JSON (JSONL) - each message is a complete JSON object followed by a newline (`\n`, 0x0A).

## Connection Roles

| Role | Description | Initiates connection? |
|------|-------------|----------------------|
| **App** (log source) | Sends logs, uses `TimberBrowser` | Yes |
| **Viewer** (log sink) | Receives logs, uses `TimberAdvertiser` | No |

The connection initiator is always the log source. The connection acceptor is always the log sink.

## Transport

- **Protocol:** TCP
- **TLS:** Optional (recommended for non-localhost)
- **Discovery:** Bonjour/mDNS with service type `_timber._tcp`
- **Default port:** None specified (dynamic via Bonjour)
- **Encoding:** UTF-8

## Handshake Sequence

```
App (initiator)                     Viewer (acceptor)
     |                                    |
     |======== TCP/TLS established =======|
     |                                    |
     |---- HELLO ----------------------->|  (1)
     |                                    |
     |<--- AUTH_CHALLENGE ---------------|  (2)
     |                                    |
     |---- AUTH_RESPONSE --------------->|  (3) [if auth required]
     |                                    |
     |<--- AUTH_RESULT ------------------|  (4)
     |                                    |
     |==== LOG STREAM begins ============>|  (5)
     |                                    |
```

### Step 1: HELLO (App → Viewer)

The app identifies itself immediately after connection.

```json
{
  "type": "hello",
  "version": 1,
  "app": "MyApp",
  "bundle_id": "com.example.myapp",
  "subsystem": "com.example.myapp.network",
  "capabilities": ["privacy_metadata"]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Always `"hello"` |
| `version` | integer | Yes | Protocol version (currently `1`) |
| `app` | string | Yes | Human-readable app name |
| `bundle_id` | string | No | App bundle identifier |
| `subsystem` | string | No | os_log subsystem being streamed |
| `capabilities` | string[] | No | Features the app supports |

**Capabilities:**
- `privacy_metadata` - App will include privacy annotations in log entries

### Step 2: AUTH_CHALLENGE (Viewer → App)

The viewer tells the app what authentication is required.

```json
{
  "type": "auth_challenge",
  "method": "pin",
  "privacy_policy": "full"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Always `"auth_challenge"` |
| `method` | string | Yes | `"none"`, `"pin"`, or `"token"` |
| `privacy_policy` | string | No | What data the viewer wants (see below) |

**Authentication methods:**
- `none` - No authentication required, proceed to streaming
- `pin` - 6-digit PIN code required
- `token` - Pre-shared token required

**Privacy policies:**
- `full` - Send all data unredacted (default)
- `respect` - Send privacy metadata, viewer may redact
- `redacted` - Pre-redact private/sensitive data before sending

### Step 3: AUTH_RESPONSE (App → Viewer)

If `method` was not `"none"`, the app responds with credentials.

**PIN authentication:**
```json
{
  "type": "auth_response",
  "pin": "482916"
}
```

**Token authentication:**
```json
{
  "type": "auth_response",
  "token": "YOUR_TOKEN"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Always `"auth_response"` |
| `pin` | string | Conditional | 6-digit PIN (if method was `pin`) |
| `token` | string | Conditional | Auth token (if method was `token`) |

### Step 4: AUTH_RESULT (Viewer → App)

The viewer confirms or rejects authentication.

**Success:**
```json
{
  "type": "auth_ok"
}
```

**Failure:**
```json
{
  "type": "auth_failed",
  "reason": "Invalid PIN"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | `"auth_ok"` or `"auth_failed"` |
| `reason` | string | No | Human-readable failure reason |

On `auth_failed`, the viewer SHOULD close the connection.

### Step 5: LOG STREAM (App → Viewer)

After successful auth (or immediately if `method` was `"none"`), the app streams log entries.

## Log Entry Format

```json
{
  "type": "log",
  "ts": "2025-01-15T10:30:45.123Z",
  "level": "info",
  "msg": "User john_doe logged in",
  "file": "AuthService.swift",
  "func": "login(username:password:)",
  "line": 142,
  "meta": {
    "subsystem": "com.example.auth",
    "category": "login"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Always `"log"` |
| `ts` | string | Yes | ISO8601 timestamp with milliseconds |
| `level` | string | Yes | Log level (see below) |
| `msg` | string | Yes | Log message content |
| `file` | string | Yes | Source file name (basename only) |
| `func` | string | Yes | Function/method name |
| `line` | integer | Yes | Line number |
| `meta` | object | No | Additional metadata |

**Log levels** (in order of severity):
- `trace`
- `debug`
- `info`
- `notice`
- `warning`
- `error`
- `fault`

## Privacy Metadata (Capability: `privacy_metadata`)

When the app declares `privacy_metadata` capability and the viewer requests it via `privacy_policy: "respect"`, log entries include privacy annotations:

```json
{
  "type": "log",
  "ts": "2025-01-15T10:30:45.123Z",
  "level": "info",
  "msg": "User ${0} logged in with token ${1}",
  "args": [
    {"value": "john_doe", "privacy": "private"},
    {"value": "sk_live_abc123", "privacy": "sensitive"}
  ],
  "file": "AuthService.swift",
  "func": "login()",
  "line": 142
}
```

| Privacy | Description | Viewer recommendation |
|---------|-------------|----------------------|
| `public` | Safe to display always | Show as-is |
| `private` | User-identifiable data | Redact in production views |
| `sensitive` | Secrets, tokens, passwords | Always redact unless explicit override |
| `auto` | System decides (default) | Treat as `private` |

The viewer can:
1. **Display all** - Show full values (local development)
2. **Respect privacy** - Redact `private` and `sensitive` values
3. **Full redaction** - Redact all interpolated values

### Reconstructing the message

With privacy metadata, `msg` uses `${N}` placeholders. To display:

```swift
var result = entry.msg
for (index, arg) in entry.args.enumerated() {
    let display = shouldRedact(arg.privacy) ? "<\(arg.privacy)>" : arg.value
    result = result.replacingOccurrences(of: "${\(index)}", with: display)
}
```

## Control Messages (Future)

Reserved message types for future bidirectional control:

| Type | Direction | Purpose |
|------|-----------|---------|
| `pause` | Viewer → App | Temporarily stop streaming |
| `resume` | Viewer → App | Resume streaming |
| `filter` | Viewer → App | Set minimum level filter |
| `ping` | Either | Keep-alive |
| `pong` | Either | Keep-alive response |

## Error Handling

### Connection errors
- If TCP connection drops, the app should attempt reconnection with exponential backoff
- Maximum retry attempts: implementation-defined (suggested: 5)

### Protocol errors
- Unknown message types should be ignored (forward compatibility)
- Missing required fields should close the connection
- Invalid JSON should close the connection

## Version Negotiation

Currently single version (`1`). Future versions:

1. App sends `"version": N` in HELLO (highest it supports)
2. Viewer responds with `"version": M` in AUTH_CHALLENGE (highest it supports, ≤ N)
3. Both use version M for the session

If viewer doesn't recognize the version, it sends `auth_failed` with reason `"Unsupported protocol version"`.

## Security Considerations

### TLS
- RECOMMENDED for any non-localhost connection
- Self-signed certificates acceptable for local development
- Certificate pinning recommended for production cloud logging

### PIN codes
- 6 digits provides 1,000,000 combinations
- Rate limiting recommended (e.g., 3 attempts per minute)
- PINs should be single-use or time-limited

### Token authentication
- Tokens should be cryptographically random (≥128 bits entropy)
- Tokens should be stored securely (Keychain on Apple platforms)
- Tokens can be revoked server-side for cloud logging

### Privacy
- `sensitive` data (passwords, tokens) should never be logged in production
- Viewers should default to redacting `private` and `sensitive` data
- Cloud logging services MUST respect privacy annotations

## Example Session

```
→ {"type":"hello","version":1,"app":"MyApp","subsystem":"com.example","capabilities":["privacy_metadata"]}
← {"type":"auth_challenge","method":"none","privacy_policy":"full"}
← {"type":"auth_ok"}
→ {"type":"log","ts":"2025-01-15T10:30:45.123Z","level":"info","msg":"App started","file":"App.swift","func":"main()","line":12}
→ {"type":"log","ts":"2025-01-15T10:30:45.456Z","level":"debug","msg":"Loading config","file":"Config.swift","func":"load()","line":34}
→ {"type":"log","ts":"2025-01-15T10:30:46.789Z","level":"info","msg":"User logged in","file":"Auth.swift","func":"login()","line":89}
...
```

## Appendix: JSON Schemas

### HelloMessage
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["type", "version", "app"],
  "properties": {
    "type": {"const": "hello"},
    "version": {"type": "integer", "minimum": 1},
    "app": {"type": "string"},
    "bundle_id": {"type": "string"},
    "subsystem": {"type": "string"},
    "capabilities": {"type": "array", "items": {"type": "string"}}
  }
}
```

### LogEntry
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["type", "ts", "level", "msg", "file", "func", "line"],
  "properties": {
    "type": {"const": "log"},
    "ts": {"type": "string", "format": "date-time"},
    "level": {"enum": ["trace", "debug", "info", "notice", "warning", "error", "fault"]},
    "msg": {"type": "string"},
    "file": {"type": "string"},
    "func": {"type": "string"},
    "line": {"type": "integer"},
    "args": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["value", "privacy"],
        "properties": {
          "value": {"type": "string"},
          "privacy": {"enum": ["public", "private", "sensitive", "auto"]}
        }
      }
    },
    "meta": {"type": "object"}
  }
}
```
