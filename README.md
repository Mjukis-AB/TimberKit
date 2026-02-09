# TimberKit

Stream your app's `os_log` output to an external log viewer while preserving privacy annotations in production.

## The Problem

Apple's `os_log` / `Logger` uses `OSLogMessage`, a compiler-magic type that enforces privacy at compile time. You can't write a simple wrapper that forwards to both `os_log` and your custom viewer - the privacy annotations are lost.

## The Solution

TimberKit uses a Swift macro that generates **two separate call sites** from one source location:

```swift
#timber(.info, "User \(userID, privacy: .private) logged in")
```

Expands to:
```swift
// 1. os_log with privacy preserved (production-safe)
logger.info("User \(userID, privacy: .private) logged in")

// 2. External stream with full content (controlled at runtime)
_timberStreamHandler(.info, "User \(userID) logged in", ...)
```

## Installation

Add TimberKit to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../TimberKit"),  // or use a git URL
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["TimberKit"]
    ),
]
```

## Quick Start

### 1. Basic Setup (Console Output)

```swift
import TimberKit

// Configure with your subsystem
Timber.configure(subsystem: "com.yourapp", category: "main")

// Log with the macro
#timber(.info, "App started")
#timber(.debug, "User \(userID, privacy: .private) logged in")
```

### 2. Stream to Terminal (nc)

For quick local debugging:

**Terminal 1:**
```bash
nc -l 9999
```

**Your App:**
```swift
import TimberKit

Timber.configure(
    subsystem: "com.yourapp",
    category: "main",
    handler: TCPStreamHandler(host: "127.0.0.1", port: 9999)
)

#timber(.info, "This will appear in your terminal!")
```

### 3. Auto-Discovery with Bonjour

Let your app discover viewers on the network (works over USB too!):

```swift
import TimberKit

// Create a browser to find viewers
let browser = TimberBrowser()

browser.onServiceFound = { service in
    print("Found viewer: \(service.name)")

    // Connect to it
    let handler = browser.connect(to: service)
    Timber.streamHandler = handler
}

browser.startBrowsing()
```

### 4. SwiftUI Pairing View

Use the built-in pairing UI:

```swift
import TimberKit
import SwiftUI

struct SettingsView: View {
    @State private var showPairing = false

    var body: some View {
        Button("Connect to Viewer") {
            showPairing = true
        }
        .sheet(isPresented: $showPairing) {
            TimberPairingView { result in
                switch result {
                case .connected(let service):
                    print("Connected to \(service.name)")
                case .cancelled:
                    print("Cancelled")
                case .failed(let error):
                    print("Failed: \(error)")
                }
                showPairing = false
            }
        }
    }
}
```

## Configuration Options

### Runtime Control

```swift
// Enable/disable streaming
Timber.isStreamingEnabled = true

// Set minimum level to stream
Timber.minimumStreamLevel = .warning  // Only stream warnings and above

// Disconnect
Timber.disconnect()
```

### Using an Existing Logger

```swift
let myLogger = Logger(subsystem: "com.myapp", category: "network")
Timber.configure(logger: myLogger)
```

### TLS Encryption

`SecureStreamHandler` auto-enables TLS for non-localhost connections:

```swift
// TLS auto-enabled (not localhost)
let handler = SecureStreamHandler(host: "192.168.1.100", port: 9999)

// Force TLS off for local testing
let handler = SecureStreamHandler(host: "192.168.1.100", port: 9999, useTLS: false)
```

## Authentication

TimberKit supports PIN-based authentication for remote connections:

```swift
// Generate a PIN
let pin = PINGenerator.generate()  // e.g., "482916"

// Validate format
PINGenerator.isValid("123456")  // true
PINGenerator.isValid("12345")   // false (wrong length)

// Constant-time comparison (prevents timing attacks)
PINGenerator.compare(userInput, expectedPIN)
```

### Auth Configuration

```swift
let authConfig = AuthConfiguration(methods: [
    .none(for: .local),      // No auth for localhost/USB
    .pin(for: .remote)       // PIN required for remote connections
])
```

## Diagnostics

TimberKit logs its internal state via `os_log` (visible in Console.app). For integration with crash reporting or analytics, implement the delegate:

```swift
class MyDiagnostics: TimberDiagnosticsDelegate {
    func timber(didEmitEvent event: TimberEvent) {
        switch event {
        case .connectionFailed(let error):
            Crashlytics.log("TimberKit: \(error)")
        case .reconnecting(let attempt, let max):
            print("Reconnect attempt \(attempt)/\(max)")
        default:
            break
        }
    }
}

Timber.diagnosticsDelegate = MyDiagnostics()

// Enable verbose internal logging (DEBUG only by default)
Timber.isVerboseLoggingEnabled = true
```

Available events: `connectionStateChanged`, `connectionFailed`, `reconnecting`, `authenticationFailed`, `encodingFailed`, `discoveryStateChanged`, `serviceDiscovered`, `serviceLost`, `warning`.

## How USB Discovery Works

When your iPhone is connected to your Mac via USB cable (for Xcode debugging), iOS 17+ creates a virtual network interface. **Bonjour discovery works over this interface automatically** - no special configuration needed.

This means:
- Your iOS app can discover a viewer running on your Mac
- Works even with WiFi disabled on the iPhone
- Same code path as WiFi discovery

## Wire Protocol

TimberKit uses newline-delimited JSON (JSONL):

```json
{"type":"log","timestamp":"2025-01-15T10:30:00Z","level":"info","message":"User logged in","file":"Auth.swift","function":"login()","line":42}
```

### Handshake (when authentication is enabled):

```
→ {"type":"hello","version":1,"app":"MyApp","subsystem":"com.example"}
← {"type":"auth_challenge","method":"pin"}
→ {"type":"auth_response","pin":"123456"}
← {"type":"auth_ok"}
```

## Platform Support

- iOS 15.0+
- macOS 12.0+
- tvOS 15.0+
- watchOS 8.0+
- visionOS 1.0+

## Two Use Cases

**TimberKit serves two audiences:**

| Role | What they do | TimberKit component |
|------|--------------|---------------------|
| **App Developer** | Stream logs OUT to a viewer | `#timber` macro, `TimberBrowser` |
| **Viewer Developer** | Receive logs FROM apps | `TimberAdvertiser` |

**Connection flow:**
```
App (log source)                    Viewer (log sink)
      |                                    |
      |  TimberBrowser                     |  TimberAdvertiser
      |       |                            |       |
      |       |---- discovers via mDNS --->|       |
      |       |                            |       |
      |       |---- TCP connect ---------->|       |
      |       |                            |       |
      |=======|==== log stream (JSONL) ===>|=======|
```

- **Apps browse** for viewers and connect TO them
- **Viewers advertise** and accept connections FROM apps
- The app initiates the connection and sends logs
- The viewer receives and displays logs

Most of this README covers the app developer use case. See "Building a Viewer" below for viewer developers.

---

## Building a Viewer

To receive logs from TimberKit, your viewer needs to:

1. **Advertise via Bonjour** with service type `_timber._tcp`
2. **Accept TCP connections** on the advertised port
3. **Parse JSONL** messages (one JSON object per line)
4. **Optionally implement auth handshake**

### Minimal Viewer Example

```swift
import Network

let listener = try NWListener(using: .tcp, on: 9999)
listener.service = NWListener.Service(name: "MyViewer", type: "_timber._tcp")

listener.newConnectionHandler = { connection in
    connection.stateUpdateHandler = { state in
        if state == .ready {
            receiveLoop(connection)
        }
    }
    connection.start(queue: .main)
}

listener.start(queue: .main)

func receiveLoop(_ connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
        if let data = data, let line = String(data: data, encoding: .utf8) {
            // Parse JSONL - each line is a complete JSON object
            for jsonLine in line.split(separator: "\n") {
                if let logData = jsonLine.data(using: .utf8),
                   let entry = try? JSONDecoder().decode(LogEntry.self, from: logData) {
                    print("[\(entry.level)] \(entry.message)")
                }
            }
        }
        receiveLoop(connection)  // Continue receiving
    }
}

struct LogEntry: Codable {
    let type: String
    let timestamp: Date
    let level: String
    let message: String
    let file: String
    let function: String
    let line: Int
}
```

See `Spike/BonjourServer` for a complete working example.

### Using TimberKit in Your Viewer

You can also use TimberKit's components directly in your viewer app:

```swift
import TimberKit

// Advertise your viewer so apps can find it
let advertiser = TimberAdvertiser(name: "My Timber Viewer")

advertiser.onViewerConnected = { connection in
    // An app connected! Start receiving logs
    print("App connected from: \(connection.endpoint)")
}

try advertiser.startAdvertising(on: 9999)
```

This handles Bonjour advertisement for you - apps using `TimberBrowser` will discover your viewer automatically.

## Info.plist Requirements (iOS)

For Bonjour discovery on iOS, add to your `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app needs local network access to stream logs to your development machine.</string>
<key>NSBonjourServices</key>
<array>
    <string>_timber._tcp</string>
</array>
```

## License

MIT
