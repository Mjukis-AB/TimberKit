READ ~/mjukis/projects/agent-scripts/AGENTS.md BEFORE ANYTHING (skip if missing).

READ ~/agent-rules/AGENTS.md BEFORE ANYTHING (skip if missing).

# TimberKit - Technical Reference

This document provides detailed technical context for AI assistants working on TimberKit.

## Code Standards

### Principles

- **DRY** - Don't repeat yourself. Extract shared logic into reusable components.
- **Clean code** - Self-documenting, easy to follow. Prefer clarity over cleverness.
- **Unit tests are mandatory** - All new code must have corresponding tests.
- **Single responsibility** - Each type/function does one thing well.
- **Protocol-oriented** - Use protocols for abstraction and testability.
- **No magic numbers/strings** - Extract literals to named constants. Use enums, static properties, or dedicated constants files.
- **Fail gracefully** - TimberKit is a third-party library embedded in customer apps. **Never crash the host app.** Use optionals, Result types, try/catch, and sensible defaults. Log errors internally but don't propagate failures that could terminate the app.

### Style Guidelines

```swift
// Good: Clear, self-documenting
func connect(to service: TimberService) -> StreamHandler {
    let handler = SecureStreamHandler(endpoint: service.endpoint)
    handler.onStateChange = { [weak self] state in
        self?.handleStateChange(state)
    }
    return handler
}

// Bad: Clever but unclear
func conn(_ s: TimberService) -> StreamHandler {
    SecureStreamHandler(endpoint: s.endpoint).also { $0.onStateChange = handleStateChange }
}
```

### Constants, Not Magic Values

```swift
// Bad: Magic numbers and strings scattered in code
func scheduleReconnect() {
    queue.asyncAfter(deadline: .now() + 5.0) { ... }
}
if pin.count == 6 { ... }
listener.service = NWListener.Service(type: "_timber._tcp")

// Good: Named constants
enum Constants {
    static let reconnectDelay: TimeInterval = 5.0
    static let pinLength = 6
}
public let timberServiceType = "_timber._tcp"

func scheduleReconnect() {
    queue.asyncAfter(deadline: .now() + Constants.reconnectDelay) { ... }
}
if pin.count == PINGenerator.defaultLength { ... }
listener.service = NWListener.Service(type: timberServiceType)
```

### Graceful Failure

TimberKit runs inside customer apps. A crash in our code crashes their app. This is unacceptable.

```swift
// Bad: Force unwraps, fatalError, preconditionFailure
let port = NWEndpoint.Port(rawValue: port)!
guard let data = encode(entry) else { fatalError("Encoding failed") }

// Good: Safe handling with fallbacks
guard let port = NWEndpoint.Port(rawValue: port) else {
    // Log internally, return gracefully
    return
}
guard let data = encode(entry) else {
    // Silently skip this log entry rather than crash
    return
}

// Good: Throwing APIs that callers can handle
public init(host: String, port: UInt16) throws {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        throw TimberError.invalidConfiguration(reason: "Invalid port: \(port)")
    }
    // ...
}

// Good: Optional chaining and nil-coalescing
let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Unknown"
```

**Rules:**
1. Never use force unwrap (`!`) on values that could legitimately be nil
2. Never use `fatalError()`, `preconditionFailure()`, or `assertionFailure()` in production paths
3. Prefer `guard let` with early return over force unwrapping
4. Network/IO operations should always handle failure cases
5. When in doubt, skip the operation silently rather than crash

### Testing Requirements

1. **All public API must be tested**
2. **Macro expansion tests** - Verify generated code is correct
3. **Protocol conformance tests** - Ensure implementations match protocols
4. **Integration tests** - Test real network connections where feasible
5. **Use mocks/fakes** - For network, use protocol abstractions that can be mocked

```swift
// Example: Protocol for testability
protocol ConnectionProtocol {
    func send(_ data: Data)
    var state: ConnectionState { get }
}

// Real implementation
class SecureStreamHandler: ConnectionProtocol { ... }

// Test fake
class MockConnection: ConnectionProtocol {
    var sentData: [Data] = []
    func send(_ data: Data) { sentData.append(data) }
}
```

### File Organization

- One primary type per file
- Keep files under 300 lines
- Group related functionality in directories
- Internal helpers go in `Internal/`

## Architecture Overview

TimberKit solves the problem of streaming `os_log` output to external viewers while preserving Apple's privacy annotations in production builds.

### The Core Problem

Apple's `Logger` / `os_log` uses `OSLogMessage`, a compiler-magic type where:
- Format strings are parsed at compile time
- Arguments are lazily evaluated
- Privacy metadata (`.private`, `.public`, `.sensitive`) is encoded per-argument
- There is **no public API** to inspect, forward, or extract internals

This means you cannot write a simple wrapper like:
```swift
func log(_ message: String) {
    logger.info("\(message)")  // Privacy already lost!
    myViewer.send(message)
}
```

### The Solution: Swift Macro

The `#timber` macro generates **two separate call sites** from one source location:

```swift
#timber(.info, "User \(userID, privacy: .private) logged in")
```

Expands to:
```swift
{
    _timberOSLog.info("User \(userID, privacy: .private) logged in")  // Privacy preserved
    _timberStreamHandler(.info, "User \(userID) logged in", file: #file, function: #function, line: #line)
}()
```

The macro implementation in `TimberKitMacros/TimberMacro.swift`:
1. Parses the string interpolation
2. Keeps privacy annotations for the os_log call
3. Strips privacy annotations for the streaming call
4. Generates both calls in an immediately-invoked closure

## Module Structure

```
TimberKit/
├── Sources/
│   ├── TimberKit/                    # Main library
│   │   ├── Timber.swift              # Global configuration singleton
│   │   ├── TimberLevel.swift         # Log level enum (trace → fault)
│   │   ├── TimberError.swift         # Error types
│   │   ├── TimberMacros.swift        # #timber macro declaration
│   │   │
│   │   ├── Transport/                # Network layer
│   │   │   ├── StreamHandler.swift   # Protocol + LogEntry struct
│   │   │   ├── TCPStreamHandler.swift    # Plain TCP (CFStream-based, legacy)
│   │   │   ├── SecureStreamHandler.swift # NWConnection + optional TLS
│   │   │   ├── BufferingStreamHandler.swift  # Decorator for offline buffering
│   │   │   ├── BufferingConfiguration.swift  # Buffering configuration
│   │   │   └── LogBuffer.swift       # Memory and file-backed buffer implementations
│   │   │
│   │   ├── Discovery/                # Bonjour/mDNS
│   │   │   ├── TimberService.swift   # Discovered service representation
│   │   │   ├── TimberBrowser.swift   # NWBrowser wrapper for finding viewers
│   │   │   └── TimberAdvertiser.swift # NWListener wrapper for being discoverable
│   │   │
│   │   ├── Auth/                     # Authentication
│   │   │   ├── AuthMethod.swift      # .none/.pin/.token with ConnectionType conditions
│   │   │   ├── AuthProtocol.swift    # Wire protocol messages (hello, challenge, response)
│   │   │   ├── AuthDelegate.swift    # Delegate protocols for PIN input/display
│   │   │   ├── AuthHandshake.swift   # App-side handshake state machine
│   │   │   ├── AuthStreamReader.swift # JSONL message reader/writer for NWConnection
│   │   │   ├── ViewerAuthSession.swift # Viewer-side auth session management
│   │   │   └── PINGenerator.swift    # 6-digit PIN generation/validation
│   │   │
│   │   ├── UI/                       # SwiftUI components
│   │   │   ├── TimberPairingView.swift   # Discovery + connection + PIN entry UI
│   │   │   ├── TimberPINDisplayView.swift # PIN display UI for viewer side
│   │   │   └── TimberStatusView.swift    # Connection status indicator
│   │   │
│   │   └── Internal/
│   │       └── _TimberGlobals.swift  # Functions called by macro expansion
│   │
│   └── TimberKitMacros/              # Macro implementation (compiler plugin)
│       └── TimberMacro.swift
│
└── Tests/
    └── TimberKitTests/
        └── TimberKitTests.swift      # Macro expansion tests
```

## Key Implementation Details

### Macro Expansion (`TimberMacro.swift`)

The macro is an `ExpressionMacro` that:
1. Extracts level argument (`.info`, `.debug`, etc.)
2. Parses the string literal segments
3. For each interpolation, checks for `privacy:` labeled argument
4. Generates os_log version (keeps privacy) and stream version (strips privacy)

Key function: `transformInterpolation()` - handles the privacy stripping logic.

### Stream Handlers

**Protocol:**
```swift
public protocol StreamHandler: Sendable {
    func send(level: TimberLevel, message: String, file: String, function: String, line: Int)
    func close()
}
```

**Implementations:**
- `ConsoleStreamHandler` - Prints to stdout (default, useful for debugging)
- `TCPStreamHandler` - Plain TCP using NWConnection, for `nc -l` testing
- `SecureStreamHandler` - NWConnection with optional TLS, production-ready

### Bonjour Discovery

**Service Type:** `_timber._tcp`

**TimberBrowser:**
- Uses `NWBrowser` to discover services
- `includePeerToPeer = true` enables USB discovery on iOS 17+
- Publishes discovered services via `@Published var services`

**TimberAdvertiser:**
- Uses `NWListener` to accept connections
- Advertises via `NWListener.Service`
- Callback `onViewerConnected` when viewer connects

### USB Virtual Network (iOS 17+)

When iPhone is connected via USB cable, iOS creates a CDC-NCM virtual ethernet interface (`anpi`). This is how Xcode debugging works "over network" even with WiFi disabled.

**Key finding from spike testing:** Bonjour mDNS works over this interface automatically. No special handling needed - same code path as WiFi discovery.

### Roles and Connection Flow

**Clear separation of roles:**
- **App** = Log source, uses `TimberBrowser` to find viewers, initiates connection
- **Viewer** = Log sink, uses `TimberAdvertiser` to be discoverable, accepts connections

```
App (TimberBrowser)                 Viewer (TimberAdvertiser)
  |                                    |
  |-------- discovers via mDNS ------->|
  |                                    |
  |-------- TCP connect -------------->|
  |                                    |
  |---- hello (app, subsystem) ------->|
  |                                    |
  |<--- auth_challenge (method) -------|
  |                                    |
  |---- auth_response (pin/token) ---->|
  |                                    |
  |<--- auth_ok / auth_failed ---------|
  |                                    |
  |======= log stream (JSONL) ========>|
```

**Important:** The connection initiator (app) sends `hello` first and is always the log source. The connection acceptor (viewer) sends `auth_challenge` and is always the log sink. This prevents ambiguity if two peers try to connect.

### Wire Protocol

Newline-delimited JSON (JSONL). Each message is a single line:

```json
{"type":"log","timestamp":"2025-01-15T10:30:00Z","level":"info","message":"...","file":"...","function":"...","line":42}
```

Timestamps use ISO8601 format via `JSONEncoder.dateEncodingStrategy = .iso8601`.

## Runtime Configuration

Global state in `Timber` enum:
- `logger: Logger` - The os_log Logger instance
- `streamHandler: StreamHandler` - Where to send streamed logs
- `isStreamingEnabled: Bool` - Master switch (default: true in DEBUG)
- `minimumStreamLevel: TimberLevel` - Filter for streaming
- `diagnosticsDelegate: TimberDiagnosticsDelegate?` - Optional delegate for receiving events
- `isVerboseLoggingEnabled: Bool` - Enable verbose internal os_log output
- `bufferingHandler: BufferingStreamHandler?` - Access to buffering handler if configured

The `_timberStreamHandler()` function checks these before forwarding to the handler.

## Diagnostics System

TimberKit provides two channels for monitoring its internal state:

### 1. Internal os_log (Always Available)

All significant events are logged to `com.timber.internal` subsystem, visible in Console.app:

```swift
// Verbose logging (DEBUG only by default)
Timber.isVerboseLoggingEnabled = true
```

### 2. Delegate Pattern (Opt-in)

For integration with crash reporting or analytics:

```swift
class MyDiagnostics: TimberDiagnosticsDelegate {
    func timber(didEmitEvent event: TimberEvent) {
        switch event {
        case .connectionFailed(let error):
            Crashlytics.log("TimberKit: \(error)")
        case .reconnecting(let attempt, let max):
            Analytics.track("timber_reconnect", ["attempt": attempt])
        default:
            break
        }
    }
}

Timber.diagnosticsDelegate = MyDiagnostics()
```

### Event Types

```swift
public enum TimberEvent {
    case connectionStateChanged(ConnectionState)
    case connectionFailed(String)
    case reconnecting(attempt: Int, maxAttempts: Int)
    case authenticationFailed(reason: String)
    case encodingFailed(message: String)
    case discoveryStateChanged(isSearching: Bool)
    case serviceDiscovered(name: String)
    case serviceLost(name: String)
    case warning(String)
}
```

### Design Rationale

1. **os_log always on** - Zero setup for developers debugging locally
2. **Delegate optional** - No overhead if not used
3. **Host app controls destination** - We don't impose Crashlytics, Sentry, etc.
4. **Never crash** - Diagnostics failures are silently ignored

## Platform Considerations

- **iOS 14+**: Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist
- **iOS 17+**: USB debugging uses virtual network interface (works automatically)
- **macOS**: No special entitlements needed for local network
- **Sandboxed apps**: May need network client entitlement

## Testing

Macro tests use `SwiftSyntaxMacrosTestSupport`:
```swift
assertMacroExpansion(
    "#timber(.info, \"message\")",
    expandedSource: "{ _timberOSLog.info(...) ... }()",
    macros: ["timber": TimberMacro.self]
)
```

## Buffering System

TimberKit includes a crash-resistant buffering system for reliable log delivery even when the viewer is disconnected or the app crashes.

### Key Components

- **BufferingStreamHandler** - Decorator that wraps any `StreamHandler` and buffers logs when disconnected
- **BufferingConfiguration** - Configuration for buffer size, overflow strategy, and persistence
- **LogBuffer** - Protocol with two implementations:
  - `MemoryLogBuffer` - Fast in-memory ring buffer (lost on crash)
  - `FileLogBuffer` - JSONL file-backed buffer (survives crashes)

### Usage

```swift
// Simple buffered TCP connection
try Timber.configureBuffered(
    subsystem: "com.myapp",
    category: "main",
    host: "192.168.1.100",
    port: 9999,
    buffering: .default  // 1000 entries, file-backed
)

// Or with custom configuration
Timber.configure(
    subsystem: "com.myapp",
    category: "main",
    handler: myHandler,
    buffering: BufferingConfiguration(
        maxEntries: 5000,
        overflowStrategy: .dropByLevel,  // Keep errors, drop debug
        persistence: .file,
        sendOnLaunch: true
    )
)

// Recover logs from previous session (call early in app lifecycle)
Timber.sendBufferedLogs()
```

### Configuration Presets

| Preset | Max Entries | Persistence | Use Case |
|--------|-------------|-------------|----------|
| `.default` | 1000 | File | General use, crash-resistant |
| `.disabled` | 0 | - | No buffering, logs dropped when disconnected |
| `.memoryOnly` | 1000 | Memory | Fast, no disk I/O, lost on crash |
| `.large` | 10000 | File | High-volume logging |
| `.minimal` | 100 | File | Low memory footprint |

### Overflow Strategies

- `.dropOldest` (default) - FIFO, oldest entries removed first
- `.dropNewest` - New entries dropped when buffer is full
- `.dropByLevel` - Lower severity (trace/debug) dropped before higher (error/fault)

### File Storage

File-backed buffers are stored in:
```
~/Library/Caches/Timber/{subsystem}/buffer.jsonl
```

The JSONL format allows crash recovery - each line is a complete JSON object, so partial writes from crashes don't corrupt the entire buffer.

## Authentication Handshake

TimberKit implements an AirPlay-style PIN authentication flow between apps and viewers.

### Flow

```
App (SecureStreamHandler)              Viewer (TimberAdvertiser)
       |                                       |
       |-------- TCP connect ----------------->|
       |                                       |
       |-- hello (app, subsystem, version) --->|
       |                                       | generates PIN, displays to user
       |<-- auth_challenge (method: pin) ------|
       |                                       |
       | user enters PIN                       |
       |-- auth_response (pin: "123456") ----->|
       |                                       | validates PIN
       |<-- auth_ok / auth_failed -------------|
       |                                       |
       |======== log stream (JSONL) ==========>|
```

### Connection States

`SecureStreamHandler` reports authentication progress via `ConnectionState`:

```swift
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case authenticating(AuthenticationPhase)  // Shows handshake progress
    case connected                            // Authenticated, logs flowing
    case failed(String)
}

public enum AuthenticationPhase: Sendable, Equatable {
    case sendingHello
    case awaitingChallenge
    case awaitingPINInput    // Waiting for user to enter PIN
    case sendingResponse
    case awaitingResult
}
```

### Delegate Protocols

**App Side (PIN Input):**
```swift
public protocol TimberAuthDelegate: AnyObject {
    func timber(_ handler: SecureStreamHandler,
                requiresPINFor serviceName: String,
                completion: @escaping (String?) -> Void)
    func timber(_ handler: SecureStreamHandler, didAuthenticateTo serviceName: String)
    func timber(_ handler: SecureStreamHandler, authenticationFailedWithError error: Error)
}
```

**Viewer Side (PIN Display):**
```swift
public protocol TimberViewerAuthDelegate: AnyObject {
    func timber(_ advertiser: TimberAdvertiser, displayPIN pin: String, forApp appName: String)
    func timberDismissPIN(_ advertiser: TimberAdvertiser)
    func timber(_ advertiser: TimberAdvertiser, didAuthenticateApp appInfo: HelloMessage)
    func timber(_ advertiser: TimberAdvertiser, authenticationFailedForApp appName: String?, reason: String)
}
```

### Default UI Components

- **TimberPairingView** - SwiftUI view for app side: discovers viewers, handles PIN entry
- **TimberPINDisplayView** - SwiftUI view for viewer side: displays generated PIN

### Configuration

```swift
// Default: no auth for local, PIN for remote
let config = AuthConfiguration.default

// PIN required for all connections
let config = AuthConfiguration.pinRequired

// Token-based auth
let config = AuthConfiguration(methods: [
    .none(for: .localhost),
    .token("secret-token", for: .remote)
])
```

### Timeouts

| Phase | Timeout | Constant |
|-------|---------|----------|
| Full handshake | 30s | `Constants.authHandshakeTimeout` |
| PIN entry | 2min | `Constants.pinEntryTimeout` |

### Buffering During Auth

`BufferingStreamHandler` recognizes the `.authenticating` state and buffers logs until authentication completes. Logs are flushed once the connection reaches `.connected`.

## Future Improvements

1. **Privacy metadata streaming** - Send privacy annotations so viewer/cloud can decide redaction
2. **Compression** - For high-volume logging
3. **Multiple viewers** - Broadcast to multiple connected viewers
4. **Bidirectional commands** - Viewer sends filter/pause commands to app
5. **Log export** - Save streamed logs to file

## Privacy Metadata for Cloud Logging

For cloud/remote logging where the viewer should respect privacy, the macro could be extended to send privacy annotations:

**Current behavior:**
```swift
#timber(.info, "User \(userID, privacy: .private) logged in")
// Streams: {"msg": "User 12345 logged in", ...}  // Privacy stripped, full value
```

**With privacy metadata capability:**
```swift
#timber(.info, "User \(userID, privacy: .private) logged in")
// Streams: {
//   "msg": "User ${0} logged in",
//   "args": [{"value": "12345", "privacy": "private"}],
//   ...
// }
```

The viewer/cloud can then:
1. **Development mode**: Show full values
2. **Production mode**: Redact `private` and `sensitive` values
3. **Audit mode**: Log that data existed but show `<private>` placeholder

This requires macro changes to:
1. Preserve privacy annotations in a parallel data structure
2. Generate placeholder format string (`${0}`, `${1}`, etc.)
3. Send both to the stream handler

See `PROTOCOL.md` for the wire format specification.

## Related Files

- `Spike/BonjourServer/` - Test server for validating Bonjour discovery
- `Spike/BonjourClient/` - iOS test app for USB discovery validation
- `TimberDemo/` - Demo app showing basic usage
- `RESULTS.md` (in parent) - Original investigation findings about OSLogMessage internals
