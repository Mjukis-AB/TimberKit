import Foundation
import os

/// Global configuration and control for Timber logging
public enum Timber {
    // MARK: - Configuration

    /// The os_log subsystem (e.g., "com.myapp.networking")
    /// Included in streamed log entries for filtering/grouping
    public private(set) static var subsystem: String = Constants.defaultSubsystem

    /// The os_log category within the subsystem (e.g., "requests")
    /// Included in streamed log entries for filtering/grouping
    public private(set) static var category: String = Constants.defaultCategory

    /// Explicitly configured bundle identifier
    /// When set, this takes precedence over #dsohandle resolution
    public private(set) static var bundleIdentifier: String?

    /// The os_log Logger instance used by #timber macro
    public static var logger: Logger = Logger(
        subsystem: Constants.defaultSubsystem,
        category: Constants.defaultCategory
    )

    /// Delegate for receiving diagnostic events from TimberKit
    /// Set this to integrate with your crash reporting or analytics system
    public static weak var diagnosticsDelegate: TimberDiagnosticsDelegate? {
        get { TimberDiagnostics.delegate }
        set { TimberDiagnostics.delegate = newValue }
    }

    /// Whether verbose internal logging is enabled
    /// When true, logs additional debug information to os_log
    public static var isVerboseLoggingEnabled: Bool {
        get { TimberDiagnostics.isVerbose }
        set { TimberDiagnostics.isVerbose = newValue }
    }

    /// The streaming handler for sending logs to external viewer
    public static var streamHandler: StreamHandler = ConsoleStreamHandler()

    /// Controls whether logs are streamed to the external handler
    public static var isStreamingEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Minimum level to stream (logs below this level are not streamed)
    public static var minimumStreamLevel: TimberLevel = .trace

    // MARK: - Configuration Methods

    /// Configure Timber with a subsystem and category
    public static func configure(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        logger = Logger(subsystem: subsystem, category: category)
    }

    /// Configure Timber with a subsystem, category, and bundle identifier
    /// - Parameters:
    ///   - subsystem: The os_log subsystem
    ///   - category: The os_log category
    ///   - bundleContaining: Any class from your framework/app to identify the bundle
    public static func configure(
        subsystem: String,
        category: String,
        bundleContaining type: AnyClass
    ) {
        self.subsystem = subsystem
        self.category = category
        self.bundleIdentifier = BundleResolver.bundleIdentifier(containing: type)
        logger = Logger(subsystem: subsystem, category: category)
    }

    /// Configure Timber with an existing Logger
    /// - Note: You must also provide subsystem/category since Logger doesn't expose these
    public static func configure(
        logger: Logger,
        subsystem: String,
        category: String
    ) {
        self.subsystem = subsystem
        self.category = category
        self.logger = logger
    }

    /// Configure Timber with an existing Logger and bundle identifier
    public static func configure(
        logger: Logger,
        subsystem: String,
        category: String,
        bundleContaining type: AnyClass
    ) {
        self.subsystem = subsystem
        self.category = category
        self.bundleIdentifier = BundleResolver.bundleIdentifier(containing: type)
        self.logger = logger
    }

    /// Configure Timber with a custom stream handler
    public static func configure(
        subsystem: String,
        category: String,
        handler: StreamHandler
    ) {
        self.subsystem = subsystem
        self.category = category
        logger = Logger(subsystem: subsystem, category: category)
        streamHandler = handler
    }

    /// Configure Timber with a custom stream handler and bundle identifier
    public static func configure(
        subsystem: String,
        category: String,
        bundleContaining type: AnyClass,
        handler: StreamHandler
    ) {
        self.subsystem = subsystem
        self.category = category
        self.bundleIdentifier = BundleResolver.bundleIdentifier(containing: type)
        logger = Logger(subsystem: subsystem, category: category)
        streamHandler = handler
    }

    /// Configure Timber with an existing Logger and custom stream handler
    /// - Note: You must also provide subsystem/category since Logger doesn't expose these
    public static func configure(
        logger: Logger,
        subsystem: String,
        category: String,
        handler: StreamHandler
    ) {
        self.subsystem = subsystem
        self.category = category
        self.logger = logger
        self.streamHandler = handler
    }

    /// Full configuration with all options
    public static func configure(
        subsystem: String,
        category: String,
        bundleContaining type: AnyClass? = nil,
        handler: StreamHandler,
        streamingEnabled: Bool,
        minimumLevel: TimberLevel = .trace
    ) {
        self.subsystem = subsystem
        self.category = category
        if let type = type {
            self.bundleIdentifier = BundleResolver.bundleIdentifier(containing: type)
        }
        logger = Logger(subsystem: subsystem, category: category)
        streamHandler = handler
        isStreamingEnabled = streamingEnabled
        minimumStreamLevel = minimumLevel
    }

    /// Resolve bundle identifier for a log entry
    /// - Parameter dsoHandle: The #dsohandle from the call site (fallback if bundleIdentifier not configured)
    /// - Returns: Bundle identifier or nil
    internal static func resolveBundleIdentifier(dsoHandle: UnsafeRawPointer?) -> String? {
        // Explicit configuration takes precedence
        if let configured = bundleIdentifier {
            return configured
        }
        // Fall back to dsohandle resolution
        if let handle = dsoHandle {
            return BundleResolver.bundleIdentifier(from: handle)
        }
        return nil
    }

    // MARK: - Buffered Connection

    /// Configure Timber with a buffered stream handler for crash-resistant logging
    ///
    /// Buffered handlers store logs locally when disconnected and send them when
    /// the connection is established. File-backed buffers survive app crashes.
    ///
    /// - Parameters:
    ///   - subsystem: The os_log subsystem
    ///   - category: The os_log category
    ///   - handler: The underlying stream handler to wrap
    ///   - buffering: Buffering configuration (default: crash-resistant file-backed)
    public static func configure(
        subsystem: String,
        category: String,
        handler: StreamHandler,
        buffering: BufferingConfiguration
    ) {
        self.subsystem = subsystem
        self.category = category
        logger = Logger(subsystem: subsystem, category: category)

        if buffering.isEnabled {
            streamHandler = BufferingStreamHandler(
                wrapping: handler,
                configuration: buffering,
                subsystem: subsystem
            )
        } else {
            streamHandler = handler
        }
    }

    /// Configure with a buffered TCP connection
    ///
    /// Creates a crash-resistant logging setup that buffers logs to disk
    /// when the viewer is disconnected.
    ///
    /// - Parameters:
    ///   - subsystem: The os_log subsystem
    ///   - category: The os_log category
    ///   - host: TCP host (default: localhost)
    ///   - port: TCP port (default: 9999)
    ///   - buffering: Buffering configuration (default: file-backed)
    public static func configureBuffered(
        subsystem: String,
        category: String,
        host: String = "127.0.0.1",
        port: UInt16 = 9999,
        buffering: BufferingConfiguration = .default
    ) throws {
        let handler = try TCPStreamHandler(host: host, port: port)
        configure(
            subsystem: subsystem,
            category: category,
            handler: handler,
            buffering: buffering
        )
    }

    /// Send any buffered logs from previous sessions
    ///
    /// Call this on app launch to send logs that were buffered before a crash
    /// or termination. Only effective if using a BufferingStreamHandler with
    /// file-backed persistence.
    ///
    /// ```swift
    /// // In AppDelegate or App init
    /// Timber.sendBufferedLogs()
    /// ```
    public static func sendBufferedLogs() {
        if let bufferingHandler = streamHandler as? BufferingStreamHandler {
            bufferingHandler.sendBufferedLogs()
        }
    }

    /// Access the buffering handler if one is configured
    ///
    /// Useful for monitoring buffer state or manually triggering flushes.
    public static var bufferingHandler: BufferingStreamHandler? {
        streamHandler as? BufferingStreamHandler
    }

    // MARK: - Connection Control

    /// Disconnect from the current viewer
    public static func disconnect() {
        streamHandler.close()
    }

    /// Connect to a specific host and port (manual connection)
    /// - Throws: TimberError.invalidConfiguration if port is invalid
    public static func connect(to host: String, port: UInt16) throws {
        streamHandler = try TCPStreamHandler(host: host, port: port)
    }
}
