import Foundation
import Network

/// A stream handler wrapper that buffers log entries when disconnected
///
/// Wraps any `StreamHandler` and provides:
/// - Buffering when the underlying handler is disconnected
/// - Automatic flush when reconnected
/// - Crash-resistant file-backed storage (optional)
/// - Recovery of buffered logs from previous session
///
/// ```swift
/// let tcpHandler = try TCPStreamHandler(host: "192.168.1.100", port: 9999)
/// let buffered = BufferingStreamHandler(
///     wrapping: tcpHandler,
///     configuration: .default
/// )
/// Timber.streamHandler = buffered
/// ```
public final class BufferingStreamHandler: StreamHandler, @unchecked Sendable {
    private let wrappedHandler: StreamHandler
    private let buffer: LogBuffer
    private let configuration: BufferingConfiguration
    private let queue = DispatchQueue(label: "timber.buffering")
    private let lock = NSLock()

    private var _isConnected = false
    private var isConnected: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isConnected
        }
        set {
            lock.lock()
            _isConnected = newValue
            lock.unlock()
        }
    }

    /// Callback when connection state changes
    public var onConnectionStateChanged: ((Bool) -> Void)?

    /// Create a buffering stream handler
    /// - Parameters:
    ///   - handler: The underlying handler to wrap
    ///   - configuration: Buffering configuration
    ///   - subsystem: Subsystem name (used for file storage path)
    public init(
        wrapping handler: StreamHandler,
        configuration: BufferingConfiguration = .default,
        subsystem: String = "default"
    ) {
        self.wrappedHandler = handler
        self.configuration = configuration

        // Create appropriate buffer based on configuration
        if configuration.isEnabled {
            switch configuration.persistence {
            case .memory:
                self.buffer = MemoryLogBuffer(
                    capacity: configuration.maxEntries,
                    overflowStrategy: configuration.overflowStrategy
                )
            case .file, .fileAt:
                if let fileURL = configuration.bufferFileURL(forSubsystem: subsystem) {
                    self.buffer = FileLogBuffer(
                        fileURL: fileURL,
                        capacity: configuration.maxEntries,
                        overflowStrategy: configuration.overflowStrategy
                    )
                } else {
                    // Fallback to memory if file URL couldn't be created
                    TimberDiagnostics.logWarning("Could not create buffer file, falling back to memory")
                    self.buffer = MemoryLogBuffer(
                        capacity: configuration.maxEntries,
                        overflowStrategy: configuration.overflowStrategy
                    )
                }
            }
        } else {
            // Disabled - use zero-capacity memory buffer (effectively no buffering)
            self.buffer = MemoryLogBuffer(capacity: 0, overflowStrategy: .dropNewest)
        }

        // Set up connection state monitoring if handler supports it
        setupConnectionMonitoring()
    }

    /// Send buffered logs from previous session
    /// Call this on app launch if you want to recover logs from a crash
    public func sendBufferedLogs() {
        guard configuration.sendOnLaunch else { return }

        queue.async { [weak self] in
            self?.flushBuffer()
        }
    }

    // MARK: - StreamHandler Protocol

    public func send(
        level: TimberLevel,
        message: String,
        bundleIdentifier: String?,
        file: String,
        function: String,
        line: Int
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            bundleIdentifier: bundleIdentifier,
            subsystem: Timber.subsystem,
            category: Timber.category,
            file: file,
            function: function,
            line: line
        )

        queue.async { [weak self] in
            guard let self = self else { return }

            if self.isConnected {
                // Connected - send directly
                self.sendEntry(entry)
            } else {
                // Disconnected - buffer it
                if self.configuration.isEnabled {
                    self.buffer.append(entry)
                    TimberDiagnostics.log("Buffered log entry (buffer size: \(self.buffer.count))")
                }
                // If buffering disabled and disconnected, log is lost
            }
        }
    }

    public func close() {
        wrappedHandler.close()
        isConnected = false
    }

    // MARK: - Connection State Management

    /// Call this when the underlying connection becomes available
    public func connectionEstablished() {
        let wasConnected = isConnected
        isConnected = true

        if !wasConnected {
            TimberDiagnostics.log("Connection established, flushing buffer")
            queue.async { [weak self] in
                self?.flushBuffer()
            }
            onConnectionStateChanged?(true)
        }
    }

    /// Call this when the underlying connection is lost
    public func connectionLost() {
        isConnected = false
        TimberDiagnostics.log("Connection lost, buffering enabled")
        onConnectionStateChanged?(false)
    }

    // MARK: - Private Helpers

    private func setupConnectionMonitoring() {
        // If wrapped handler is a SecureStreamHandler, monitor its state
        if let secureHandler = wrappedHandler as? SecureStreamHandler {
            secureHandler.onStateChange = { [weak self] state in
                switch state {
                case .connected:
                    self?.connectionEstablished()
                case .disconnected, .failed:
                    self?.connectionLost()
                case .connecting, .authenticating:
                    // Still buffering during connection and auth
                    break
                }
            }
            // Check initial state
            if secureHandler.state == .connected {
                isConnected = true
            }
        } else {
            // For other handlers, assume connected initially
            // They'll need to call connectionLost/connectionEstablished manually
            isConnected = true
        }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }

        let entries = buffer.drainAll()
        TimberDiagnostics.log("Flushing \(entries.count) buffered entries")

        for entry in entries {
            sendEntry(entry)
        }

        TimberDiagnostics.emit(.warning("Flushed \(entries.count) buffered log entries"))
    }

    private func sendEntry(_ entry: LogEntry) {
        wrappedHandler.send(
            level: TimberLevel(rawValue: entry.level) ?? .info,
            message: entry.message,
            bundleIdentifier: entry.bundleIdentifier,
            file: entry.file,
            function: entry.function,
            line: entry.line
        )
    }
}

// MARK: - Convenience Initializers

extension BufferingStreamHandler {
    /// Create a buffering handler with a TCP handler
    public static func tcp(
        host: String = "127.0.0.1",
        port: UInt16 = 9999,
        buffering: BufferingConfiguration = .default,
        subsystem: String = "default"
    ) throws -> BufferingStreamHandler {
        let handler = try TCPStreamHandler(host: host, port: port)
        return BufferingStreamHandler(
            wrapping: handler,
            configuration: buffering,
            subsystem: subsystem
        )
    }

    /// Create a buffering handler with a secure handler
    public static func secure(
        host: String,
        port: UInt16,
        useTLS: Bool? = nil,
        buffering: BufferingConfiguration = .default,
        subsystem: String = "default"
    ) throws -> BufferingStreamHandler {
        let handler = try SecureStreamHandler(host: host, port: port, useTLS: useTLS)
        return BufferingStreamHandler(
            wrapping: handler,
            configuration: buffering,
            subsystem: subsystem
        )
    }

    /// Create a buffering handler for a Bonjour endpoint
    public static func bonjour(
        endpoint: Network.NWEndpoint,
        useTLS: Bool = false,
        buffering: BufferingConfiguration = .default,
        subsystem: String = "default"
    ) -> BufferingStreamHandler {
        let handler = SecureStreamHandler(endpoint: endpoint, useTLS: useTLS)
        return BufferingStreamHandler(
            wrapping: handler,
            configuration: buffering,
            subsystem: subsystem
        )
    }
}
