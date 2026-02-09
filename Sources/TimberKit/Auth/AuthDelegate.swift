import Foundation

// MARK: - App Side (PIN Input)

/// Delegate for app-side PIN input during authentication
///
/// Implement this protocol to provide custom UI for PIN entry.
/// The default `TimberPairingView` implements this automatically.
///
/// ```swift
/// class MyAuthHandler: TimberAuthDelegate {
///     func timber(_ handler: SecureStreamHandler,
///                 requiresPINFor serviceName: String,
///                 completion: @escaping (String?) -> Void) {
///         showMyCustomPINDialog { enteredPIN in
///             completion(enteredPIN)  // nil to cancel
///         }
///     }
/// }
///
/// let handler = browser.connect(to: service)
/// handler.authDelegate = MyAuthHandler()
/// ```
public protocol TimberAuthDelegate: AnyObject {
    /// Called when PIN entry is required to complete authentication
    ///
    /// - Parameters:
    ///   - handler: The stream handler requesting authentication
    ///   - serviceName: Name of the viewer being connected to
    ///   - completion: Call with the entered PIN, or nil to cancel authentication
    ///
    /// - Note: This is called on the main thread. The completion can be called
    ///   from any thread.
    func timber(
        _ handler: SecureStreamHandler,
        requiresPINFor serviceName: String,
        completion: @escaping (String?) -> Void
    )

    /// Called when authentication completes successfully
    ///
    /// - Parameters:
    ///   - handler: The stream handler that completed authentication
    ///   - serviceName: Name of the connected viewer
    ///
    /// - Note: This is called on the main thread.
    func timber(
        _ handler: SecureStreamHandler,
        didAuthenticateTo serviceName: String
    )

    /// Called when authentication fails
    ///
    /// - Parameters:
    ///   - handler: The stream handler that failed authentication
    ///   - error: The error that caused the failure
    ///
    /// - Note: This is called on the main thread.
    func timber(
        _ handler: SecureStreamHandler,
        authenticationFailedWithError error: Error
    )
}

// MARK: - Default Implementations

public extension TimberAuthDelegate {
    func timber(_ handler: SecureStreamHandler, didAuthenticateTo serviceName: String) {
        // Default: no-op
    }

    func timber(_ handler: SecureStreamHandler, authenticationFailedWithError error: Error) {
        // Default: no-op
    }
}

// MARK: - Viewer Side (PIN Display)

/// Delegate for viewer-side PIN display during authentication
///
/// Implement this protocol to show the generated PIN to the user.
/// The viewer must display this PIN so the app user can enter it.
///
/// ```swift
/// class MyPINDisplay: TimberViewerAuthDelegate {
///     func timber(_ advertiser: TimberAdvertiser,
///                 displayPIN pin: String,
///                 forApp appName: String) {
///         showPINOverlay(pin: pin, app: appName)
///     }
///
///     func timberDismissPIN(_ advertiser: TimberAdvertiser) {
///         hidePINOverlay()
///     }
/// }
///
/// let advertiser = TimberAdvertiser(name: "My Viewer")
/// advertiser.authDelegate = MyPINDisplay()
/// ```
public protocol TimberViewerAuthDelegate: AnyObject {
    /// Called when a PIN should be displayed to the user
    ///
    /// The viewer should prominently display this PIN so the app user
    /// can enter it on their device. The PIN is valid until either
    /// `timberDismissPIN` is called or authentication times out.
    ///
    /// - Parameters:
    ///   - advertiser: The advertiser handling the connection
    ///   - pin: The 6-digit PIN to display
    ///   - appName: Name of the connecting app (from hello message)
    ///
    /// - Note: This is called on the main thread.
    func timber(
        _ advertiser: TimberAdvertiser,
        displayPIN pin: String,
        forApp appName: String
    )

    /// Called when the PIN display should be dismissed
    ///
    /// This is called when:
    /// - Authentication succeeds (correct PIN entered)
    /// - Authentication fails (wrong PIN, timeout, or cancelled)
    /// - The connection is closed
    ///
    /// - Parameter advertiser: The advertiser handling the connection
    ///
    /// - Note: This is called on the main thread.
    func timberDismissPIN(_ advertiser: TimberAdvertiser)

    /// Called when a new app has authenticated successfully
    ///
    /// - Parameters:
    ///   - advertiser: The advertiser handling the connection
    ///   - appInfo: Information about the connected app
    ///
    /// - Note: This is called on the main thread.
    func timber(
        _ advertiser: TimberAdvertiser,
        didAuthenticateApp appInfo: HelloMessage
    )

    /// Called when authentication fails
    ///
    /// - Parameters:
    ///   - advertiser: The advertiser handling the connection
    ///   - appName: Name of the app that failed to authenticate (if known)
    ///   - reason: The reason for failure
    ///
    /// - Note: This is called on the main thread.
    func timber(
        _ advertiser: TimberAdvertiser,
        authenticationFailedForApp appName: String?,
        reason: String
    )
}

// MARK: - Default Implementations

public extension TimberViewerAuthDelegate {
    func timber(_ advertiser: TimberAdvertiser, didAuthenticateApp appInfo: HelloMessage) {
        // Default: no-op
    }

    func timber(_ advertiser: TimberAdvertiser, authenticationFailedForApp appName: String?, reason: String) {
        // Default: no-op
    }
}

// MARK: - Authentication Phase

/// Represents the current phase of authentication handshake
public enum AuthenticationPhase: Sendable, Equatable {
    /// Sending hello message to viewer
    case sendingHello
    /// Waiting for auth challenge from viewer
    case awaitingChallenge
    /// Waiting for user to enter PIN
    case awaitingPINInput
    /// Sending auth response with PIN
    case sendingResponse
    /// Waiting for auth result from viewer
    case awaitingResult
}
