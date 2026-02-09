import Foundation
import os

/// Events emitted by TimberKit for diagnostics and monitoring
public enum TimberEvent: Sendable {
    /// Connection state changed
    case connectionStateChanged(ConnectionState)

    /// Failed to connect to viewer
    case connectionFailed(String)

    /// Attempting to reconnect
    case reconnecting(attempt: Int, maxAttempts: Int)

    /// Authentication handshake started
    case authenticationStarted

    /// PIN input required from user
    case authenticationPINRequired

    /// User entered PIN
    case authenticationPINEntered

    /// Authentication succeeded
    case authenticationSucceeded

    /// Authentication failed
    case authenticationFailed(reason: String)

    /// Failed to encode log entry (data will be dropped)
    case encodingFailed(message: String)

    /// Bonjour discovery state changed
    case discoveryStateChanged(isSearching: Bool)

    /// Service discovered or lost
    case serviceDiscovered(name: String)
    case serviceLost(name: String)

    /// General warning (non-fatal issue)
    case warning(String)
}

/// Delegate protocol for receiving TimberKit diagnostic events
///
/// Implement this to integrate TimberKit diagnostics with your
/// crash reporting or analytics system.
///
/// ```swift
/// class MyDiagnostics: TimberDiagnosticsDelegate {
///     func timber(didEmitEvent event: TimberEvent) {
///         switch event {
///         case .connectionFailed(let error):
///             Crashlytics.log("TimberKit: \(error)")
///         default:
///             break
///         }
///     }
/// }
///
/// Timber.diagnosticsDelegate = MyDiagnostics()
/// ```
public protocol TimberDiagnosticsDelegate: AnyObject, Sendable {
    /// Called when TimberKit emits a diagnostic event
    func timber(didEmitEvent event: TimberEvent)
}

/// Internal logging and diagnostics for TimberKit
///
/// This provides two channels for diagnostics:
/// 1. **os_log** - Always available, visible in Console.app during development
/// 2. **Delegate** - Optional, for integrating with crash reporting/analytics
///
/// Usage within TimberKit:
/// ```swift
/// TimberDiagnostics.log("Connection established", level: .info)
/// TimberDiagnostics.emit(.connectionFailed("Timeout"))
/// ```
public enum TimberDiagnostics {
    /// Internal os_log logger for TimberKit's own diagnostics
    /// Visible in Console.app under subsystem "com.timber.internal"
    private static let internalLogger = Logger(
        subsystem: "com.timber.internal",
        category: "diagnostics"
    )

    /// Optional delegate for receiving diagnostic events
    /// Set this to integrate with your crash reporting or analytics
    public static weak var delegate: TimberDiagnosticsDelegate?

    /// Whether verbose internal logging is enabled
    /// When true, logs additional debug information via os_log
    public static var isVerbose: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // MARK: - Internal Logging (os_log)

    /// Log a message to TimberKit's internal os_log
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Log level (default: .debug)
    internal static func log(_ message: String, level: OSLogType = .debug) {
        switch level {
        case .debug:
            if isVerbose {
                internalLogger.debug("\(message, privacy: .public)")
            }
        case .info:
            internalLogger.info("\(message, privacy: .public)")
        case .error:
            internalLogger.error("\(message, privacy: .public)")
        case .fault:
            internalLogger.fault("\(message, privacy: .public)")
        default:
            internalLogger.log("\(message, privacy: .public)")
        }
    }

    /// Log an error condition
    internal static func logError(_ message: String) {
        log(message, level: .error)
    }

    /// Log a warning
    internal static func logWarning(_ message: String) {
        log(message, level: .info)
        emit(.warning(message))
    }

    // MARK: - Event Emission (Delegate)

    /// Emit a diagnostic event to the delegate
    /// - Parameter event: The event to emit
    internal static func emit(_ event: TimberEvent) {
        // Always log significant events internally
        switch event {
        case .connectionFailed(let error):
            log("Connection failed: \(error)", level: .error)
        case .authenticationStarted:
            log("Authentication handshake started", level: .debug)
        case .authenticationPINRequired:
            log("PIN input required", level: .info)
        case .authenticationPINEntered:
            log("PIN entered by user", level: .debug)
        case .authenticationSucceeded:
            log("Authentication succeeded", level: .info)
        case .authenticationFailed(let reason):
            log("Authentication failed: \(reason)", level: .error)
        case .encodingFailed(let message):
            log("Encoding failed for message: \(message)", level: .error)
        case .reconnecting(let attempt, let max):
            log("Reconnecting attempt \(attempt)/\(max)", level: .info)
        case .connectionStateChanged(let state):
            log("Connection state: \(state)", level: .debug)
        case .discoveryStateChanged(let isSearching):
            log("Discovery: \(isSearching ? "started" : "stopped")", level: .debug)
        case .serviceDiscovered(let name):
            log("Service discovered: \(name)", level: .info)
        case .serviceLost(let name):
            log("Service lost: \(name)", level: .info)
        case .warning(let message):
            log("Warning: \(message)", level: .info)
        }

        // Forward to delegate if set
        delegate?.timber(didEmitEvent: event)
    }

    // MARK: - Convenience Methods

    /// Report a connection failure
    internal static func reportConnectionFailed(_ error: Error) {
        emit(.connectionFailed(error.localizedDescription))
    }

    /// Report a connection failure with string message
    internal static func reportConnectionFailed(_ message: String) {
        emit(.connectionFailed(message))
    }

    /// Report authentication failure
    internal static func reportAuthFailed(reason: String) {
        emit(.authenticationFailed(reason: reason))
    }

    /// Report reconnection attempt
    internal static func reportReconnecting(attempt: Int, maxAttempts: Int) {
        emit(.reconnecting(attempt: attempt, maxAttempts: maxAttempts))
    }

    /// Report encoding failure (log entry will be dropped)
    internal static func reportEncodingFailed(message: String) {
        emit(.encodingFailed(message: message))
    }
}
