import Combine
import Foundation
import Network

/// Advertises a Timber viewer so apps can discover and connect to it.
///
/// Use this in your **viewer** (the log sink) to be discoverable by apps.
/// Apps use `TimberBrowser` to find your viewer and connect.
///
/// ```swift
/// let advertiser = TimberAdvertiser(name: "My Viewer")
/// advertiser.onViewerConnected = { connection in
///     // App connected, start receiving logs
/// }
/// try advertiser.startAdvertising(on: 9999)
/// ```
///
/// ## Connection Flow
/// ```
/// App (TimberBrowser)              Viewer (TimberAdvertiser)
///        |                                    |
///        |-------- discovers via mDNS ------->|
///        |                                    |
///        |-------- TCP connect -------------->|
///        |                                    |
///        |-- hello (app name, subsystem) ---->|
///        |<-- auth_challenge (method) --------|
///        |-- auth_response (pin/token) ------>|
///        |<-- auth_ok -----------------------|
///        |                                    |
///        |======== log stream (JSONL) =======>|
/// ```
///
/// - Note: Apps use `TimberBrowser` to find and connect to viewers.
public final class TimberAdvertiser: ObservableObject, @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "timber.advertiser")
    private var pendingSessions: [ObjectIdentifier: ViewerAuthSession] = [:]
    private let sessionsLock = NSLock()

    /// The service name being advertised
    public let serviceName: String

    /// Metadata to advertise in TXT record
    private let metadata: [String: String]

    /// The port being advertised
    public private(set) var port: UInt16?

    /// Whether the advertiser is active
    @Published public private(set) var isAdvertising: Bool = false

    // MARK: - Authentication

    /// Authentication configuration
    public var authConfiguration: AuthConfiguration = .default

    /// Delegate for PIN display during authentication
    public weak var authDelegate: TimberViewerAuthDelegate?

    /// Whether authentication is enabled
    /// When false, connections are accepted without handshake
    public var authEnabled: Bool = true

    // MARK: - Callbacks

    /// Callback when an app connects and authenticates successfully
    ///
    /// This is the recommended callback for handling authenticated connections.
    public var onAuthenticatedConnection: ((NWConnection, HelloMessage) -> Void)?

    /// Callback when a viewer connects (legacy, before auth)
    ///
    /// - Note: Deprecated. Use `onAuthenticatedConnection` for authenticated connections.
    @available(*, deprecated, message: "Use onAuthenticatedConnection for authenticated connections")
    public var onViewerConnected: ((NWConnection) -> Void)?

    /// Create an advertiser
    /// - Parameters:
    ///   - name: Service name (defaults to app name)
    ///   - metadata: Additional metadata to advertise in TXT record
    public init(
        name: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.serviceName = name
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? Constants.defaultAppName
        self.metadata = metadata
    }

    /// Start advertising and listening for viewer connections
    /// - Parameter port: Specific port to listen on (0 for automatic)
    public func startAdvertising(on port: UInt16 = 0) throws {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        if port == 0 {
            listener = try NWListener(using: params)
        } else if let listenPort = NWEndpoint.Port(rawValue: port) {
            listener = try NWListener(using: params, on: listenPort)
        } else {
            throw TimberError.invalidConfiguration(reason: "Invalid port: \(port)")
        }

        // Configure Bonjour advertisement with TXT record metadata
        let txtRecord = buildTXTRecord()
        listener?.service = NWListener.Service(
            name: serviceName,
            type: timberServiceType,
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isAdvertising = true
                    if let port = self?.listener?.port?.rawValue {
                        self?.port = port
                    }
                case .failed, .cancelled:
                    self?.isAdvertising = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    /// Stop advertising
    public func stopAdvertising() {
        listener?.cancel()
        listener = nil

        DispatchQueue.main.async {
            self.isAdvertising = false
            self.port = nil
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                if self.authEnabled {
                    self.startAuthSession(for: connection)
                } else {
                    // Skip auth, accept immediately
                    DispatchQueue.main.async {
                        // Create a mock HelloMessage for legacy callback
                        let mockHello = HelloMessage(app: "Unknown", subsystem: "unknown")
                        self.onAuthenticatedConnection?(connection, mockHello)
                    }
                }
            case .failed, .cancelled:
                self.removeSession(for: connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func startAuthSession(for connection: NWConnection) {
        let session = ViewerAuthSession(
            connection: connection,
            configuration: authConfiguration,
            queue: queue
        )

        let connectionId = ObjectIdentifier(connection)

        // Store session
        sessionsLock.lock()
        pendingSessions[connectionId] = session
        sessionsLock.unlock()

        // Set up session callbacks
        session.onPINGenerated = { [weak self] pin, appName in
            guard let self = self else { return }
            self.authDelegate?.timber(self, displayPIN: pin, forApp: appName)
        }

        session.onDismissPIN = { [weak self] in
            guard let self = self else { return }
            self.authDelegate?.timberDismissPIN(self)
        }

        session.onAuthenticated = { [weak self] appInfo in
            guard let self = self else { return }
            self.removeSession(for: connection)
            self.authDelegate?.timber(self, didAuthenticateApp: appInfo)
            self.onAuthenticatedConnection?(connection, appInfo)
        }

        session.onRejected = { [weak self] reason in
            guard let self = self else { return }
            self.removeSession(for: connection)
            self.authDelegate?.timber(self, authenticationFailedForApp: session.appInfo?.app, reason: reason)
            connection.cancel()
        }

        session.start()
    }

    private func removeSession(for connection: NWConnection) {
        let connectionId = ObjectIdentifier(connection)
        sessionsLock.lock()
        pendingSessions.removeValue(forKey: connectionId)
        sessionsLock.unlock()
    }

    private func buildTXTRecord() -> NWTXTRecord {
        var txtRecord = NWTXTRecord()

        // Add user-provided metadata
        for (key, value) in metadata {
            txtRecord[key] = value
        }

        return txtRecord
    }

    deinit {
        stopAdvertising()
    }
}
