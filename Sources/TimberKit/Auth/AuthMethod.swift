import Foundation

/// Connection type for conditional authentication
public enum ConnectionType: Sendable {
    case any           // All connections
    case localhost     // 127.0.0.1, ::1
    case usb           // USB virtual network (anpi interface on iOS 17+)
    case local         // localhost OR usb
    case remote        // Everything else

    /// Check if this connection type matches a given host
    public func matches(host: String, isUSB: Bool = false) -> Bool {
        switch self {
        case .any:
            return true
        case .localhost:
            return Constants.isLocalhost(host)
        case .usb:
            return isUSB
        case .local:
            return Constants.isLocalhost(host) || isUSB
        case .remote:
            return !ConnectionType.local.matches(host: host, isUSB: isUSB)
        }
    }
}

/// Authentication method for Timber connections
public enum AuthMethod: Sendable {
    /// No authentication required
    case none(for: ConnectionType = .any)

    /// PIN code authentication (6-digit code)
    case pin(for: ConnectionType = .any)

    /// Token-based authentication
    case token(String, for: ConnectionType = .any)

    /// Get the connection type this auth method applies to
    public var connectionType: ConnectionType {
        switch self {
        case .none(let type), .pin(let type), .token(_, let type):
            return type
        }
    }

    /// Check if this auth method requires authentication for the given connection
    public func requiresAuth(for host: String, isUSB: Bool = false) -> Bool {
        guard connectionType.matches(host: host, isUSB: isUSB) else {
            return false
        }

        switch self {
        case .none:
            return false
        case .pin, .token:
            return true
        }
    }
}

/// Authentication configuration for Timber
public struct AuthConfiguration: Sendable {
    /// Authentication methods in priority order
    public let methods: [AuthMethod]

    /// Default: no auth for local, PIN for remote
    public static let `default` = AuthConfiguration(methods: [
        .none(for: .local),
        .pin(for: .remote)
    ])

    /// No authentication at all
    public static let none = AuthConfiguration(methods: [.none(for: .any)])

    /// PIN required for all connections
    public static let pinRequired = AuthConfiguration(methods: [.pin(for: .any)])

    public init(methods: [AuthMethod]) {
        self.methods = methods
    }

    /// Determine the required authentication for a connection
    public func requiredAuth(for host: String, isUSB: Bool = false) -> AuthMethod? {
        for method in methods {
            if method.connectionType.matches(host: host, isUSB: isUSB) {
                return method
            }
        }
        return nil
    }
}
