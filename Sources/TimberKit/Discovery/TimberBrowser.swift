import Combine
import Foundation
import Network

/// Browses for Timber viewer services on the local network.
///
/// Use this in your **app** (the log source) to discover viewers.
/// The browser finds advertised viewers and connects to them.
///
/// ```swift
/// let browser = TimberBrowser()
/// browser.onServiceFound = { service in
///     let handler = browser.connect(to: service)
///     Timber.streamHandler = handler
/// }
/// browser.startBrowsing()
/// ```
///
/// - Note: Viewers use `TimberAdvertiser` to be discoverable.
public final class TimberBrowser: ObservableObject, @unchecked Sendable {
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "timber.browser")

    /// Currently discovered services
    @Published public private(set) var services: [TimberService] = []

    /// Whether the browser is actively searching
    @Published public private(set) var isSearching: Bool = false

    /// Callback when services change
    public var onServicesChanged: (([TimberService]) -> Void)?

    /// Callback when a service is found
    public var onServiceFound: ((TimberService) -> Void)?

    /// Callback when a service is lost
    public var onServiceLost: ((TimberService) -> Void)?

    public init() {}

    /// Start browsing for Timber services
    public func startBrowsing() {
        guard browser == nil else { return }

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: timberServiceType, domain: Constants.bonjourDomain),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                    TimberDiagnostics.emit(.discoveryStateChanged(isSearching: true))
                case .failed, .cancelled:
                    self?.isSearching = false
                    TimberDiagnostics.emit(.discoveryStateChanged(isSearching: false))
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleResultsChange(results: results, changes: changes)
        }

        browser?.start(queue: queue)
    }

    /// Stop browsing
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil

        DispatchQueue.main.async {
            self.isSearching = false
            self.services = []
        }
    }

    private func handleResultsChange(
        results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>
    ) {
        var updatedServices: [TimberService] = []

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else {
                continue
            }

            // Extract TXT record metadata if available
            var metadata: [String: String] = [:]
            if case .bonjour(let txtRecord) = result.metadata {
                // Parse TXT record entries
                let keys = [
                    Constants.TXTRecordKey.app,
                    Constants.TXTRecordKey.version,
                    Constants.TXTRecordKey.subsystem
                ]
                for key in keys {
                    if let value = txtRecord.dictionary[key] {
                        metadata[key] = value
                    }
                }
            }

            let service = TimberService(
                name: name,
                endpoint: result.endpoint,
                metadata: metadata
            )
            updatedServices.append(service)
        }

        // Determine added/removed services
        let previousServices = Set(services)
        let newServices = Set(updatedServices)

        let added = newServices.subtracting(previousServices)
        let removed = previousServices.subtracting(newServices)

        DispatchQueue.main.async {
            self.services = updatedServices
            self.onServicesChanged?(updatedServices)

            for service in added {
                self.onServiceFound?(service)
                TimberDiagnostics.emit(.serviceDiscovered(name: service.name))
            }
            for service in removed {
                self.onServiceLost?(service)
                TimberDiagnostics.emit(.serviceLost(name: service.name))
            }
        }
    }

    /// Connect to a discovered service
    ///
    /// - Parameters:
    ///   - service: The service to connect to
    ///   - useTLS: Whether to use TLS encryption
    ///   - authConfiguration: Authentication configuration (default: .default)
    ///   - authDelegate: Delegate for PIN input during authentication
    ///   - authEnabled: Whether to perform auth handshake (default: true)
    /// - Returns: A configured SecureStreamHandler
    public func connect(
        to service: TimberService,
        useTLS: Bool = false,
        authConfiguration: AuthConfiguration = .default,
        authDelegate: TimberAuthDelegate? = nil,
        authEnabled: Bool = true
    ) -> SecureStreamHandler {
        let handler = SecureStreamHandler(endpoint: service.endpoint, useTLS: useTLS)
        handler.serviceName = service.name
        handler.authConfiguration = authConfiguration
        handler.authDelegate = authDelegate
        handler.authEnabled = authEnabled
        return handler
    }

    deinit {
        stopBrowsing()
    }
}
