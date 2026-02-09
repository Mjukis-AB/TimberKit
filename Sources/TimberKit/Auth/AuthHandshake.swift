import Foundation
import Network

/// Coordinates the authentication handshake on the app side
///
/// This class manages the state machine for authentication:
/// 1. Sends hello message after connection ready
/// 2. Receives auth challenge from viewer
/// 3. Requests PIN from delegate if needed
/// 4. Sends auth response with PIN
/// 5. Receives auth result (ok/failed)
///
/// The handshake has a configurable timeout (default 30 seconds).
/// PIN entry has a separate longer timeout (default 2 minutes).
public final class AuthHandshake: @unchecked Sendable {

    // MARK: - Types

    /// Current state of the handshake
    public enum State: Sendable, Equatable {
        case idle
        case sendingHello
        case awaitingChallenge
        case awaitingPINInput(method: String)
        case sendingResponse
        case awaitingResult
        case authenticated
        case failed(String)

        /// Convert to AuthenticationPhase for external use
        public var phase: AuthenticationPhase? {
            switch self {
            case .sendingHello: return .sendingHello
            case .awaitingChallenge: return .awaitingChallenge
            case .awaitingPINInput: return .awaitingPINInput
            case .sendingResponse: return .sendingResponse
            case .awaitingResult: return .awaitingResult
            case .idle, .authenticated, .failed: return nil
            }
        }
    }

    // MARK: - Properties

    private let connection: NWConnection
    private let configuration: AuthConfiguration
    private let appName: String
    private let subsystem: String
    private let serviceName: String
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var reader: AuthStreamReader?
    private var writer: AuthStreamWriter?
    private var handshakeTimer: DispatchSourceTimer?
    private var pinEntryTimer: DispatchSourceTimer?

    private var _state: State = .idle
    private var state: State {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _state
        }
        set {
            lock.lock()
            _state = newValue
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onStateChanged?(newValue)
            }
        }
    }

    private var pinCompletion: ((String?) -> Void)?

    // MARK: - Callbacks

    /// Called when handshake state changes
    public var onStateChanged: ((State) -> Void)?

    /// Called when PIN is required from user
    /// The closure receives the auth method (e.g., "pin") and should call
    /// `submitPIN(_:)` when the user enters the PIN.
    public var onPINRequired: ((String) -> Void)?

    /// Called when authentication succeeds
    public var onAuthenticated: (() -> Void)?

    /// Called when authentication fails
    public var onFailed: ((TimberError) -> Void)?

    // MARK: - Initialization

    /// Create an auth handshake coordinator
    ///
    /// - Parameters:
    ///   - connection: The NWConnection to authenticate over
    ///   - configuration: Auth configuration (determines if PIN is required)
    ///   - appName: Name of this app (sent in hello message)
    ///   - subsystem: Logger subsystem (sent in hello message)
    ///   - serviceName: Name of the viewer being connected to
    ///   - queue: Dispatch queue for network operations
    public init(
        connection: NWConnection,
        configuration: AuthConfiguration,
        appName: String,
        subsystem: String,
        serviceName: String,
        queue: DispatchQueue
    ) {
        self.connection = connection
        self.configuration = configuration
        self.appName = appName
        self.subsystem = subsystem
        self.serviceName = serviceName
        self.queue = queue
    }

    deinit {
        cancel()
    }

    // MARK: - Public Methods

    /// Start the authentication handshake
    ///
    /// Call this after the connection is ready (`.ready` state).
    public func start() {
        guard state == .idle else { return }

        reader = AuthStreamReader(connection: connection, queue: queue)
        writer = AuthStreamWriter(connection: connection)

        startHandshakeTimer()
        sendHello()
    }

    /// Submit PIN entered by user
    ///
    /// Call this when the user has entered the PIN in response to `onPINRequired`.
    ///
    /// - Parameter pin: The 6-digit PIN entered by user, or nil to cancel
    public func submitPIN(_ pin: String?) {
        cancelPINEntryTimer()

        guard case .awaitingPINInput = state else {
            TimberDiagnostics.logWarning("submitPIN called in unexpected state: \(state)")
            return
        }

        if let pin = pin {
            sendAuthResponse(pin: pin, token: nil)
        } else {
            // User cancelled
            fail(with: .authenticationFailed(reason: "User cancelled PIN entry"))
        }
    }

    /// Cancel the handshake
    public func cancel() {
        cancelHandshakeTimer()
        cancelPINEntryTimer()
        reader?.cancel()
        reader = nil
        writer = nil

        if case .failed = state {
            // Already failed, don't update
        } else if state != .authenticated {
            state = .failed("Cancelled")
        }
    }

    // MARK: - Private - State Machine

    private func sendHello() {
        state = .sendingHello
        TimberDiagnostics.emit(.authenticationStarted)

        let hello = HelloMessage(
            app: appName,
            subsystem: subsystem,
            version: Constants.authProtocolVersion
        )

        writer?.send(.hello(hello)) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.fail(with: .authenticationFailed(reason: error.localizedDescription))
                return
            }

            self.awaitChallenge()
        }
    }

    private func awaitChallenge() {
        state = .awaitingChallenge

        reader?.readNextMessage { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleChallengeMessage(message)
            case .failure(let error):
                self.fail(with: .authenticationFailed(reason: error.localizedDescription))
            }
        }
    }

    private func handleChallengeMessage(_ message: AuthMessage) {
        guard case .authChallenge(let challenge) = message else {
            fail(with: .authenticationFailed(reason: "Expected auth_challenge, got unexpected message"))
            return
        }

        TimberDiagnostics.log("Received auth challenge: method=\(challenge.method)")

        switch challenge.method {
        case AuthMethodIdentifier.none:
            // No auth required, send empty response
            sendAuthResponse(pin: nil, token: nil)

        case AuthMethodIdentifier.pin:
            // Need PIN from user
            requestPINFromUser(method: challenge.method)

        case AuthMethodIdentifier.token:
            // Token auth - check if we have a matching token in config
            if let token = findToken() {
                sendAuthResponse(pin: nil, token: token)
            } else {
                fail(with: .authenticationFailed(reason: "Token required but not configured"))
            }

        default:
            fail(with: .authenticationFailed(reason: "Unknown auth method: \(challenge.method)"))
        }
    }

    private func requestPINFromUser(method: String) {
        state = .awaitingPINInput(method: method)
        TimberDiagnostics.emit(.authenticationPINRequired)

        // Start longer timeout for PIN entry
        startPINEntryTimer()

        DispatchQueue.main.async { [weak self] in
            self?.onPINRequired?(method)
        }
    }

    private func sendAuthResponse(pin: String?, token: String?) {
        state = .sendingResponse

        if pin != nil {
            TimberDiagnostics.emit(.authenticationPINEntered)
        }

        // Create response based on which credential is provided
        let response: AuthResponseMessage
        if let pin = pin {
            response = AuthResponseMessage(pin: pin)
        } else if let token = token {
            response = AuthResponseMessage(token: token)
        } else {
            response = AuthResponseMessage()
        }

        writer?.send(.authResponse(response)) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.fail(with: .authenticationFailed(reason: error.localizedDescription))
                return
            }

            self.awaitResult()
        }
    }

    private func awaitResult() {
        state = .awaitingResult

        reader?.readNextMessage { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleResultMessage(message)
            case .failure(let error):
                self.fail(with: .authenticationFailed(reason: error.localizedDescription))
            }
        }
    }

    private func handleResultMessage(_ message: AuthMessage) {
        guard case .authResult(let result) = message else {
            fail(with: .authenticationFailed(reason: "Expected auth result, got unexpected message"))
            return
        }

        cancelHandshakeTimer()

        if result.success {
            state = .authenticated
            TimberDiagnostics.emit(.authenticationSucceeded)
            DispatchQueue.main.async { [weak self] in
                self?.onAuthenticated?()
            }
        } else {
            let reason = result.reason ?? "Authentication rejected"
            fail(with: .authenticationFailed(reason: reason))
        }
    }

    private func fail(with error: TimberError) {
        cancelHandshakeTimer()
        cancelPINEntryTimer()
        reader?.cancel()

        state = .failed(error.localizedDescription)
        TimberDiagnostics.emit(.authenticationFailed(reason: error.localizedDescription))

        DispatchQueue.main.async { [weak self] in
            self?.onFailed?(error)
        }
    }

    // MARK: - Private - Helpers

    private func findToken() -> String? {
        // Look for a token auth method in the configuration
        for method in configuration.methods {
            if case .token(let token, _) = method {
                return token
            }
        }
        return nil
    }

    // MARK: - Private - Timers

    private func startHandshakeTimer() {
        handshakeTimer?.cancel()
        handshakeTimer = DispatchSource.makeTimerSource(queue: queue)
        handshakeTimer?.schedule(deadline: .now() + Constants.authHandshakeTimeout)
        handshakeTimer?.setEventHandler { [weak self] in
            self?.handleHandshakeTimeout()
        }
        handshakeTimer?.resume()
    }

    private func cancelHandshakeTimer() {
        handshakeTimer?.cancel()
        handshakeTimer = nil
    }

    private func startPINEntryTimer() {
        pinEntryTimer?.cancel()
        pinEntryTimer = DispatchSource.makeTimerSource(queue: queue)
        pinEntryTimer?.schedule(deadline: .now() + Constants.pinEntryTimeout)
        pinEntryTimer?.setEventHandler { [weak self] in
            self?.handlePINEntryTimeout()
        }
        pinEntryTimer?.resume()
    }

    private func cancelPINEntryTimer() {
        pinEntryTimer?.cancel()
        pinEntryTimer = nil
    }

    private func handleHandshakeTimeout() {
        fail(with: .authenticationFailed(reason: "Handshake timeout"))
    }

    private func handlePINEntryTimeout() {
        fail(with: .authenticationFailed(reason: "PIN entry timeout"))
    }
}
