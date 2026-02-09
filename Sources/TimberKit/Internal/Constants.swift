import Foundation

/// Internal constants for TimberKit
/// Centralizes magic numbers and strings to improve maintainability
enum Constants {
    // MARK: - Network

    /// Default TCP port for local debugging (used with `nc -l`)
    static let defaultTCPPort: UInt16 = 9999

    /// Reconnect delay for TCPStreamHandler (seconds)
    static let tcpReconnectDelay: TimeInterval = 1.0

    /// Maximum reconnect attempts for SecureStreamHandler
    static let maxReconnectAttempts = 5

    /// Base delay for exponential backoff (seconds)
    static let reconnectBackoffBase: Double = 2.0

    // MARK: - Localhost Detection

    /// IPv4 loopback address
    static let localhostIPv4 = "127.0.0.1"

    /// IPv6 loopback address
    static let localhostIPv6 = "::1"

    /// Localhost hostname
    static let localhostName = "localhost"

    /// Check if a host is a localhost address
    static func isLocalhost(_ host: String) -> Bool {
        host == localhostIPv4 || host == localhostName || host == localhostIPv6
    }

    // MARK: - Authentication

    /// Timeout for entire auth handshake (seconds)
    static let authHandshakeTimeout: TimeInterval = 30.0

    /// Timeout for user to enter PIN (seconds)
    static let pinEntryTimeout: TimeInterval = 120.0

    /// Auth protocol version
    static let authProtocolVersion = 1

    // MARK: - Wire Protocol

    /// JSONL line terminator (newline)
    static let jsonlTerminator: UInt8 = 0x0A

    /// Bonjour domain for local discovery
    static let bonjourDomain = "local."

    // MARK: - Defaults

    /// Default subsystem for Timber logger
    static let defaultSubsystem = "com.timber"

    /// Default category for Timber logger
    static let defaultCategory = "default"

    /// Default app name when bundle name unavailable
    static let defaultAppName = "TimberApp"

    // MARK: - TXT Record Keys

    /// Keys used in Bonjour TXT records
    enum TXTRecordKey {
        static let app = "app"
        static let version = "version"
        static let subsystem = "subsystem"
    }
}

/// Message type identifiers for the wire protocol
/// These are the `type` field values in JSON messages
enum MessageType {
    static let log = "log"
    static let hello = "hello"
    static let authChallenge = "auth_challenge"
    static let authResponse = "auth_response"
    static let authOK = "auth_ok"
    static let authFailed = "auth_failed"
}

/// Authentication method identifiers for wire protocol
enum AuthMethodIdentifier {
    static let none = "none"
    static let pin = "pin"
    static let token = "token"
}
