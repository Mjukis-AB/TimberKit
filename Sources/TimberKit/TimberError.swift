import Foundation

/// Errors that can occur in TimberKit
public enum TimberError: Error, LocalizedError {
    case notConfigured
    case connectionFailed(underlying: Error?)
    case authenticationFailed(reason: String)
    case authenticationRequired
    case discoveryFailed(underlying: Error?)
    case noServicesFound
    case alreadyConnected
    case notConnected
    case sendFailed(underlying: Error?)
    case invalidConfiguration(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Timber has not been configured. Call Timber.configure() first."
        case .connectionFailed(let error):
            if let error = error {
                return "Connection failed: \(error.localizedDescription)"
            }
            return "Connection failed"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .authenticationRequired:
            return "Authentication is required for this connection"
        case .discoveryFailed(let error):
            if let error = error {
                return "Service discovery failed: \(error.localizedDescription)"
            }
            return "Service discovery failed"
        case .noServicesFound:
            return "No Timber services found on the network"
        case .alreadyConnected:
            return "Already connected to a viewer"
        case .notConnected:
            return "Not connected to any viewer"
        case .sendFailed(let error):
            if let error = error {
                return "Failed to send log: \(error.localizedDescription)"
            }
            return "Failed to send log"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
