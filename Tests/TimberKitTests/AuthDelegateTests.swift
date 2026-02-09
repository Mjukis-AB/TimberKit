import XCTest
@testable import TimberKit

final class AuthenticationPhaseTests: XCTestCase {

    // MARK: - Equatable Tests

    func testAuthenticationPhaseEquality() {
        XCTAssertEqual(AuthenticationPhase.sendingHello, AuthenticationPhase.sendingHello)
        XCTAssertEqual(AuthenticationPhase.awaitingChallenge, AuthenticationPhase.awaitingChallenge)
        XCTAssertEqual(AuthenticationPhase.awaitingPINInput, AuthenticationPhase.awaitingPINInput)
        XCTAssertEqual(AuthenticationPhase.sendingResponse, AuthenticationPhase.sendingResponse)
        XCTAssertEqual(AuthenticationPhase.awaitingResult, AuthenticationPhase.awaitingResult)
    }

    func testAuthenticationPhaseInequality() {
        XCTAssertNotEqual(AuthenticationPhase.sendingHello, AuthenticationPhase.awaitingChallenge)
        XCTAssertNotEqual(AuthenticationPhase.awaitingPINInput, AuthenticationPhase.sendingResponse)
    }

    // MARK: - Sendable Tests

    func testAuthenticationPhaseIsSendable() {
        // Test that AuthenticationPhase can be sent across concurrency boundaries
        let phase: AuthenticationPhase = .sendingHello

        Task {
            let _ = phase
        }
    }

    // MARK: - All Cases

    func testAllAuthenticationPhases() {
        // Ensure all expected phases exist
        let phases: [AuthenticationPhase] = [
            .sendingHello,
            .awaitingChallenge,
            .awaitingPINInput,
            .sendingResponse,
            .awaitingResult,
        ]

        XCTAssertEqual(phases.count, 5)
    }
}

final class AuthStreamErrorTests: XCTestCase {

    // MARK: - Error Description Tests

    func testCancelledErrorDescription() {
        let error = AuthStreamError.cancelled
        XCTAssertEqual(error.errorDescription, "Read cancelled")
    }

    func testConnectionClosedErrorDescription() {
        let error = AuthStreamError.connectionClosed
        XCTAssertEqual(error.errorDescription, "Connection closed")
    }

    func testNetworkErrorDescription() {
        let error = AuthStreamError.networkError("Connection reset by peer")
        XCTAssertEqual(error.errorDescription, "Network error: Connection reset by peer")
    }

    func testInvalidMessageErrorDescription() {
        let error = AuthStreamError.invalidMessage("Missing type field")
        XCTAssertEqual(error.errorDescription, "Invalid message: Missing type field")
    }

    func testTimeoutErrorDescription() {
        let error = AuthStreamError.timeout
        XCTAssertEqual(error.errorDescription, "Read timeout")
    }

    // MARK: - Error Conformance

    func testErrorConformance() {
        // Verify all errors conform to LocalizedError
        let errors: [AuthStreamError] = [
            .cancelled,
            .connectionClosed,
            .networkError("test"),
            .invalidMessage("test"),
            .timeout,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }

    // MARK: - Pattern Matching

    func testErrorPatternMatching() {
        let error: Error = AuthStreamError.networkError("test")

        if case AuthStreamError.networkError(let message) = error {
            XCTAssertEqual(message, "test")
        } else {
            XCTFail("Pattern matching failed")
        }
    }
}

final class AuthHandshakeStateTests: XCTestCase {

    // MARK: - State Equatable Tests

    func testIdleStateEquality() {
        XCTAssertEqual(AuthHandshake.State.idle, AuthHandshake.State.idle)
    }

    func testSendingHelloStateEquality() {
        XCTAssertEqual(AuthHandshake.State.sendingHello, AuthHandshake.State.sendingHello)
    }

    func testAwaitingChallengeStateEquality() {
        XCTAssertEqual(AuthHandshake.State.awaitingChallenge, AuthHandshake.State.awaitingChallenge)
    }

    func testAwaitingPINInputStateEquality() {
        XCTAssertEqual(
            AuthHandshake.State.awaitingPINInput(method: "pin"),
            AuthHandshake.State.awaitingPINInput(method: "pin")
        )
        XCTAssertNotEqual(
            AuthHandshake.State.awaitingPINInput(method: "pin"),
            AuthHandshake.State.awaitingPINInput(method: "token")
        )
    }

    func testSendingResponseStateEquality() {
        XCTAssertEqual(AuthHandshake.State.sendingResponse, AuthHandshake.State.sendingResponse)
    }

    func testAwaitingResultStateEquality() {
        XCTAssertEqual(AuthHandshake.State.awaitingResult, AuthHandshake.State.awaitingResult)
    }

    func testAuthenticatedStateEquality() {
        XCTAssertEqual(AuthHandshake.State.authenticated, AuthHandshake.State.authenticated)
    }

    func testFailedStateEquality() {
        XCTAssertEqual(
            AuthHandshake.State.failed("error"),
            AuthHandshake.State.failed("error")
        )
        XCTAssertNotEqual(
            AuthHandshake.State.failed("error1"),
            AuthHandshake.State.failed("error2")
        )
    }

    // MARK: - Phase Conversion Tests

    func testStatePhaseConversion() {
        XCTAssertEqual(AuthHandshake.State.sendingHello.phase, .sendingHello)
        XCTAssertEqual(AuthHandshake.State.awaitingChallenge.phase, .awaitingChallenge)
        XCTAssertEqual(AuthHandshake.State.awaitingPINInput(method: "pin").phase, .awaitingPINInput)
        XCTAssertEqual(AuthHandshake.State.sendingResponse.phase, .sendingResponse)
        XCTAssertEqual(AuthHandshake.State.awaitingResult.phase, .awaitingResult)
    }

    func testNonProgressStatesHaveNilPhase() {
        XCTAssertNil(AuthHandshake.State.idle.phase)
        XCTAssertNil(AuthHandshake.State.authenticated.phase)
        XCTAssertNil(AuthHandshake.State.failed("error").phase)
    }
}

final class ConnectionStateAuthTests: XCTestCase {

    // MARK: - Authenticating State Tests

    func testConnectionStateAuthenticatingEquality() {
        XCTAssertEqual(
            ConnectionState.authenticating(.sendingHello),
            ConnectionState.authenticating(.sendingHello)
        )
        XCTAssertEqual(
            ConnectionState.authenticating(.awaitingPINInput),
            ConnectionState.authenticating(.awaitingPINInput)
        )
    }

    func testConnectionStateAuthenticatingInequality() {
        XCTAssertNotEqual(
            ConnectionState.authenticating(.sendingHello),
            ConnectionState.authenticating(.awaitingChallenge)
        )
        XCTAssertNotEqual(
            ConnectionState.authenticating(.sendingHello),
            ConnectionState.connecting
        )
    }

    func testAllConnectionStates() {
        // Verify all states exist
        let states: [ConnectionState] = [
            .disconnected,
            .connecting,
            .authenticating(.sendingHello),
            .authenticating(.awaitingChallenge),
            .authenticating(.awaitingPINInput),
            .authenticating(.sendingResponse),
            .authenticating(.awaitingResult),
            .connected,
            .failed("error"),
        ]

        XCTAssertEqual(states.count, 9)
    }

    func testConnectionStateSendable() {
        // Verify ConnectionState can be passed across concurrency boundaries
        let state: ConnectionState = .authenticating(.awaitingPINInput)

        Task {
            let _ = state
        }
    }
}
