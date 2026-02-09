import Foundation
import Network

/// Connection state for SecureStreamHandler
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case authenticating(AuthenticationPhase)
    case connected  // Now means "authenticated and ready for logs"
    case failed(String)

    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.authenticating(let lhsPhase), .authenticating(let rhsPhase)):
            return lhsPhase == rhsPhase
        case (.failed(let lhsMsg), .failed(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

/// Secure stream handler using Network framework with optional TLS
public final class SecureStreamHandler: StreamHandler, @unchecked Sendable {
    private let endpoint: NWEndpoint
    private let useTLS: Bool
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "timber.secure")
    private let stateLock = NSLock()

    private var _state: ConnectionState = .disconnected
    public private(set) var state: ConnectionState {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
        }
        set {
            stateLock.lock()
            _state = newValue
            stateLock.unlock()
        }
    }

    /// Callback for state changes
    public var onStateChange: ((ConnectionState) -> Void)?

    // MARK: - Authentication

    /// Authentication configuration
    public var authConfiguration: AuthConfiguration = .default

    /// Delegate for PIN input during authentication
    public weak var authDelegate: TimberAuthDelegate?

    /// Name of the service being connected to (for PIN delegate)
    public var serviceName: String = "Viewer"

    /// Whether authentication is enabled
    /// When false, logs will stream immediately without handshake
    public var authEnabled: Bool = true

    private var handshake: AuthHandshake?

    /// Create a secure stream handler
    /// - Parameters:
    ///   - host: Target host
    ///   - port: Target port
    ///   - useTLS: Whether to use TLS encryption (default: true for non-localhost)
    /// - Throws: TimberError.invalidConfiguration if port is invalid
    public init(host: String, port: UInt16, useTLS: Bool? = nil) throws {
        self.endpoint = try makeEndpoint(host: host, port: port)

        // Auto-detect TLS: disabled for localhost, enabled otherwise
        if let useTLS = useTLS {
            self.useTLS = useTLS
        } else {
            self.useTLS = !Constants.isLocalhost(host)
        }

        connect()
    }

    /// Create from a discovered Bonjour endpoint
    public init(endpoint: NWEndpoint, useTLS: Bool = false) {
        self.endpoint = endpoint
        self.useTLS = useTLS

        connect()
    }

    private func connect() {
        // Cancel any existing connection before creating a new one
        connection?.cancel()
        connection = nil

        state = .connecting

        let params: NWParameters
        if useTLS {
            params = NWParameters(tls: tlsOptions())
        } else {
            params = NWParameters.tcp
        }

        // Enable peer-to-peer for USB/Bonjour discovery
        params.includePeerToPeer = true

        connection = NWConnection(to: endpoint, using: params)

        connection?.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }

            switch newState {
            case .ready:
                self.reconnectAttempts = 0  // Reset on successful connection
                if self.authEnabled {
                    self.startHandshake()
                } else {
                    // Skip auth, go directly to connected
                    self.state = .connected
                    self.onStateChange?(.connected)
                    TimberDiagnostics.emit(.connectionStateChanged(.connected))
                }

            case .failed(let error):
                self.handshake?.cancel()
                self.handshake = nil
                self.state = .failed(error.localizedDescription)
                self.onStateChange?(.failed(error.localizedDescription))
                TimberDiagnostics.reportConnectionFailed(error)
                // Attempt reconnect after delay
                self.scheduleReconnect()

            case .cancelled:
                self.handshake?.cancel()
                self.handshake = nil
                self.state = .disconnected
                self.onStateChange?(.disconnected)
                TimberDiagnostics.emit(.connectionStateChanged(.disconnected))

            case .waiting(let error):
                // Network path not available, keep waiting
                self.state = .failed(error.localizedDescription)
                self.onStateChange?(.failed(error.localizedDescription))
                TimberDiagnostics.logWarning("Network path unavailable: \(error.localizedDescription)")

            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    // MARK: - Authentication Handshake

    private func startHandshake() {
        guard let connection = connection else { return }

        handshake = AuthHandshake(
            connection: connection,
            configuration: authConfiguration,
            appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? Constants.defaultAppName,
            subsystem: Timber.subsystem,
            serviceName: serviceName,
            queue: queue
        )

        handshake?.onStateChanged = { [weak self] handshakeState in
            guard let self = self else { return }
            if let phase = handshakeState.phase {
                self.state = .authenticating(phase)
                self.onStateChange?(.authenticating(phase))
            }
        }

        handshake?.onPINRequired = { [weak self] _ in
            guard let self = self else { return }
            self.requestPINFromDelegate()
        }

        handshake?.onAuthenticated = { [weak self] in
            guard let self = self else { return }
            self.handshake = nil
            self.state = .connected
            self.onStateChange?(.connected)
            TimberDiagnostics.emit(.connectionStateChanged(.connected))

            // Notify delegate
            DispatchQueue.main.async {
                self.authDelegate?.timber(self, didAuthenticateTo: self.serviceName)
            }
        }

        handshake?.onFailed = { [weak self] error in
            guard let self = self else { return }
            self.handshake = nil
            self.state = .failed(error.localizedDescription)
            self.onStateChange?(.failed(error.localizedDescription))

            // Notify delegate
            DispatchQueue.main.async {
                self.authDelegate?.timber(self, authenticationFailedWithError: error)
            }

            // Schedule reconnect to try again
            self.scheduleReconnect()
        }

        handshake?.start()
    }

    private func requestPINFromDelegate() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let delegate = self.authDelegate {
                delegate.timber(self, requiresPINFor: self.serviceName) { [weak self] pin in
                    self?.handshake?.submitPIN(pin)
                }
            } else {
                // No delegate - fail auth
                TimberDiagnostics.logWarning("PIN required but no authDelegate set")
                self.handshake?.submitPIN(nil)
            }
        }
    }

    /// Submit PIN for authentication
    ///
    /// Call this if you're handling PIN input programmatically instead of using the delegate.
    public func submitPIN(_ pin: String?) {
        handshake?.submitPIN(pin)
    }

    private func tlsOptions() -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()

        // For development: skip certificate verification
        // In production, you'd want proper certificate validation
        #if DEBUG
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, _, completion in
                // Accept all certificates in DEBUG
                completion(true)
            },
            queue
        )
        #endif

        return options
    }

    private var reconnectAttempts = 0

    private func scheduleReconnect() {
        guard reconnectAttempts < Constants.maxReconnectAttempts else {
            TimberDiagnostics.logWarning("Max reconnect attempts reached")
            return
        }

        reconnectAttempts += 1
        TimberDiagnostics.reportReconnecting(
            attempt: reconnectAttempts,
            maxAttempts: Constants.maxReconnectAttempts
        )

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delay = pow(Constants.reconnectBackoffBase, Double(reconnectAttempts - 1))

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

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
            guard let self = self,
                  let connection = self.connection,
                  connection.state == .ready else {
                return
            }

            guard let data = LogEntryEncoder.shared.encode(entry) else {
                TimberDiagnostics.reportEncodingFailed(message: message)
                return
            }

            connection.send(content: data, completion: .contentProcessed { _ in
                // Connection will handle reconnection via state handler
            })
        }
    }

    public func close() {
        reconnectAttempts = Constants.maxReconnectAttempts // Prevent reconnection
        handshake?.cancel()
        handshake = nil
        connection?.cancel()
        connection = nil
        state = .disconnected
    }

    deinit {
        close()
    }
}
