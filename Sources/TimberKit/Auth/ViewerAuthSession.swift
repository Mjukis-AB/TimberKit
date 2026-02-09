import Foundation
import Network

/// Manages authentication for a single incoming connection on the viewer side
///
/// The viewer side of the auth handshake:
/// 1. Waits for hello message from app
/// 2. Generates a PIN and sends challenge
/// 3. Calls delegate to display PIN
/// 4. Receives auth response with PIN
/// 5. Validates PIN and sends result
/// 6. Calls completion with authenticated connection
public final class ViewerAuthSession: @unchecked Sendable {

    // MARK: - Types

    /// State of the viewer auth session
    public enum State: Sendable {
        case awaitingHello
        case sendingChallenge
        case awaitingResponse
        case validating
        case authenticated(HelloMessage)
        case rejected(String)
    }

    // MARK: - Properties

    private let connection: NWConnection
    private let configuration: AuthConfiguration
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var reader: AuthStreamReader?
    private var writer: AuthStreamWriter?
    private var handshakeTimer: DispatchSourceTimer?

    private var _state: State = .awaitingHello
    public var state: State {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _state
        }
        set {
            lock.lock()
            _state = newValue
            lock.unlock()
        }
    }

    /// The generated PIN for this session (viewer displays this)
    public private(set) var generatedPIN: String?

    /// Info about the connecting app
    public private(set) var appInfo: HelloMessage?

    /// The auth method we challenged for (used to validate response)
    private var challengedMethod: AuthMethod?

    // MARK: - Callbacks

    /// Called when state changes
    public var onStateChanged: ((State) -> Void)?

    /// Called when PIN should be displayed to user
    public var onPINGenerated: ((String, String) -> Void)?  // (pin, appName)

    /// Called when PIN display should be dismissed
    public var onDismissPIN: (() -> Void)?

    /// Called when authentication succeeds
    public var onAuthenticated: ((HelloMessage) -> Void)?

    /// Called when authentication fails
    public var onRejected: ((String) -> Void)?

    // MARK: - Initialization

    public init(
        connection: NWConnection,
        configuration: AuthConfiguration,
        queue: DispatchQueue
    ) {
        self.connection = connection
        self.configuration = configuration
        self.queue = queue
    }

    deinit {
        cancel()
    }

    // MARK: - Public Methods

    /// Start the authentication session
    public func start() {
        reader = AuthStreamReader(connection: connection, queue: queue)
        writer = AuthStreamWriter(connection: connection)

        startHandshakeTimer()
        awaitHello()
    }

    /// Cancel the session
    public func cancel() {
        cancelHandshakeTimer()
        reader?.cancel()
        onDismissPIN?()
    }

    // MARK: - Private - State Machine

    private func awaitHello() {
        state = .awaitingHello

        reader?.readNextMessage { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleHelloMessage(message)
            case .failure(let error):
                self.reject(reason: error.localizedDescription)
            }
        }
    }

    private func handleHelloMessage(_ message: AuthMessage) {
        guard case .hello(let hello) = message else {
            reject(reason: "Expected hello message")
            return
        }

        appInfo = hello
        TimberDiagnostics.log("Received hello from app: \(hello.app), subsystem: \(hello.subsystem)")

        // Determine auth method based on configuration
        // For viewer side, we always use remote since apps connect to us
        guard let requiredAuth = configuration.requiredAuth(for: "remote", isUSB: false) else {
            // No auth configured - allow without challenge
            sendChallenge(method: .none(for: .any))
            return
        }

        switch requiredAuth {
        case .none:
            sendChallenge(method: .none(for: .any))

        case .pin:
            generatedPIN = PINGenerator.generate()
            sendChallenge(method: .pin(for: .any))

            // Notify delegate to display PIN
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let pin = self.generatedPIN else { return }
                self.onPINGenerated?(pin, hello.app)
            }

        case .token:
            sendChallenge(method: .token("", for: .any))
        }
    }

    private func sendChallenge(method: AuthMethod) {
        state = .sendingChallenge
        challengedMethod = method

        let challenge = AuthChallengeMessage(method: method)

        writer?.send(.authChallenge(challenge)) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.reject(reason: error.localizedDescription)
                return
            }

            self.awaitResponse()
        }
    }

    private func awaitResponse() {
        state = .awaitingResponse

        reader?.readNextMessage { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleAuthResponse(message)
            case .failure(let error):
                self.reject(reason: error.localizedDescription)
            }
        }
    }

    private func handleAuthResponse(_ message: AuthMessage) {
        guard case .authResponse(let response) = message else {
            reject(reason: "Expected auth_response message")
            return
        }

        state = .validating

        // Validate based on what we challenged for
        guard let method = challengedMethod else {
            reject(reason: "No challenge was sent")
            return
        }

        switch method {
        case .none:
            // No auth required - accept
            accept()

        case .pin:
            // PIN auth - validate the PIN
            guard let expectedPIN = generatedPIN else {
                reject(reason: "PIN was not generated")
                return
            }
            guard let submittedPIN = response.pin else {
                reject(reason: "PIN required but not provided")
                return
            }
            if PINGenerator.compare(submittedPIN, expectedPIN) {
                accept()
            } else {
                reject(reason: "Invalid PIN")
            }

        case .token:
            // Token auth - validate against config
            guard let token = response.token else {
                reject(reason: "Token required but not provided")
                return
            }
            if validateToken(token) {
                accept()
            } else {
                reject(reason: "Invalid token")
            }
        }
    }

    private func validateToken(_ token: String) -> Bool {
        for method in configuration.methods {
            if case .token(let expected, _) = method {
                // Constant-time comparison for tokens too
                if token.count == expected.count {
                    var result: UInt8 = 0
                    let tokenBytes = Array(token.utf8)
                    let expectedBytes = Array(expected.utf8)
                    for (a, b) in zip(tokenBytes, expectedBytes) {
                        result |= a ^ b
                    }
                    if result == 0 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func accept() {
        cancelHandshakeTimer()

        let result = AuthResultMessage.success()
        writer?.send(.authResult(result)) { [weak self] error in
            guard let self = self else { return }

            // Dismiss PIN display
            DispatchQueue.main.async {
                self.onDismissPIN?()
            }

            if error != nil {
                // Send failed but auth was valid - still consider accepted
                TimberDiagnostics.logWarning("Failed to send auth_ok: \(error?.localizedDescription ?? "unknown")")
            }

            if let appInfo = self.appInfo {
                self.state = .authenticated(appInfo)
                TimberDiagnostics.emit(.authenticationSucceeded)
                DispatchQueue.main.async {
                    self.onAuthenticated?(appInfo)
                }
            }
        }
    }

    private func reject(reason: String) {
        cancelHandshakeTimer()

        // Dismiss PIN display
        DispatchQueue.main.async { [weak self] in
            self?.onDismissPIN?()
        }

        let result = AuthResultMessage.failure(reason: reason)
        writer?.send(.authResult(result)) { [weak self] _ in
            guard let self = self else { return }

            self.state = .rejected(reason)
            TimberDiagnostics.emit(.authenticationFailed(reason: reason))
            DispatchQueue.main.async {
                self.onRejected?(reason)
            }
        }
    }

    // MARK: - Private - Timer

    private func startHandshakeTimer() {
        handshakeTimer?.cancel()
        handshakeTimer = DispatchSource.makeTimerSource(queue: queue)
        handshakeTimer?.schedule(deadline: .now() + Constants.authHandshakeTimeout)
        handshakeTimer?.setEventHandler { [weak self] in
            self?.reject(reason: "Authentication timeout")
        }
        handshakeTimer?.resume()
    }

    private func cancelHandshakeTimer() {
        handshakeTimer?.cancel()
        handshakeTimer = nil
    }
}
