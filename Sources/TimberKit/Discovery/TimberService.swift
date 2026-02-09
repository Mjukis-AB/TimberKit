import Foundation
import Network

/// Bonjour service type for Timber
public let timberServiceType = "_timber._tcp"

/// Represents a discovered Timber viewer service
public struct TimberService: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let endpoint: NWEndpoint

    /// TXT record metadata (if available)
    public let metadata: [String: String]

    public init(name: String, endpoint: NWEndpoint, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.endpoint = endpoint
        self.metadata = metadata
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(endpoint.debugDescription)
    }

    public static func == (lhs: TimberService, rhs: TimberService) -> Bool {
        lhs.name == rhs.name && lhs.endpoint.debugDescription == rhs.endpoint.debugDescription
    }
}
