import XCTest
@testable import TimberKit

final class AuthProtocolTests: XCTestCase {

    // MARK: - HelloMessage Tests

    func testHelloMessageEncoding() throws {
        let hello = HelloMessage(app: "TestApp", subsystem: "com.test")
        let data = try JSONEncoder().encode(hello)
        let json = try JSONDecoder().decode([String: Any].self, from: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "hello")
        XCTAssertEqual(json["app"] as? String, "TestApp")
        XCTAssertEqual(json["subsystem"] as? String, "com.test")
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    func testHelloMessageDecoding() throws {
        let json = """
        {"type":"hello","version":1,"app":"MyApp","subsystem":"com.myapp"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(AuthMessage.self, from: data)

        guard case .hello(let hello) = message else {
            XCTFail("Expected hello message")
            return
        }

        XCTAssertEqual(hello.app, "MyApp")
        XCTAssertEqual(hello.subsystem, "com.myapp")
        XCTAssertEqual(hello.version, 1)
    }

    func testHelloMessageWithCustomVersion() throws {
        let hello = HelloMessage(app: "App", subsystem: "sub", version: 2)

        XCTAssertEqual(hello.version, 2)
        XCTAssertEqual(hello.type, "hello")
    }

    // MARK: - AuthChallengeMessage Tests

    func testAuthChallengeNoneEncoding() throws {
        let challenge = AuthChallengeMessage(method: .none(for: .any))
        let data = try JSONEncoder().encode(challenge)
        let json = try JSONDecoder().decode([String: String].self, from: data)

        XCTAssertEqual(json["type"], "auth_challenge")
        XCTAssertEqual(json["method"], "none")
    }

    func testAuthChallengePinEncoding() throws {
        let challenge = AuthChallengeMessage(method: .pin(for: .remote))
        let data = try JSONEncoder().encode(challenge)
        let json = try JSONDecoder().decode([String: String].self, from: data)

        XCTAssertEqual(json["type"], "auth_challenge")
        XCTAssertEqual(json["method"], "pin")
    }

    func testAuthChallengeTokenEncoding() throws {
        let challenge = AuthChallengeMessage(method: .token("secret", for: .any))
        let data = try JSONEncoder().encode(challenge)
        let json = try JSONDecoder().decode([String: String].self, from: data)

        XCTAssertEqual(json["type"], "auth_challenge")
        XCTAssertEqual(json["method"], "token")
    }

    func testAuthChallengeDecoding() throws {
        let json = """
        {"type":"auth_challenge","method":"pin"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(AuthMessage.self, from: data)

        guard case .authChallenge(let challenge) = message else {
            XCTFail("Expected auth_challenge message")
            return
        }

        XCTAssertEqual(challenge.method, "pin")
    }

    // MARK: - AuthResponseMessage Tests

    func testAuthResponseWithPinEncoding() throws {
        let response = AuthResponseMessage(pin: "123456")
        let data = try JSONEncoder().encode(response)
        let json = try JSONDecoder().decode([String: Any].self, from: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "auth_response")
        XCTAssertEqual(json["pin"] as? String, "123456")
        XCTAssertNil(json["token"] as? String)
    }

    func testAuthResponseWithTokenEncoding() throws {
        let response = AuthResponseMessage(token: "my-secret-token")
        let data = try JSONEncoder().encode(response)
        let json = try JSONDecoder().decode([String: Any].self, from: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "auth_response")
        XCTAssertNil(json["pin"] as? String)
        XCTAssertEqual(json["token"] as? String, "my-secret-token")
    }

    func testAuthResponseEmptyEncoding() throws {
        let response = AuthResponseMessage()
        let data = try JSONEncoder().encode(response)
        let json = try JSONDecoder().decode([String: Any].self, from: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "auth_response")
        XCTAssertNil(json["pin"] as? String)
        XCTAssertNil(json["token"] as? String)
    }

    func testAuthResponseDecoding() throws {
        let json = """
        {"type":"auth_response","pin":"654321"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(AuthMessage.self, from: data)

        guard case .authResponse(let response) = message else {
            XCTFail("Expected auth_response message")
            return
        }

        XCTAssertEqual(response.pin, "654321")
        XCTAssertNil(response.token)
    }

    func testAuthResponseWithTokenDecoding() throws {
        let json = """
        {"type":"auth_response","token":"secret123"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(AuthMessage.self, from: data)

        guard case .authResponse(let response) = message else {
            XCTFail("Expected auth_response message")
            return
        }

        XCTAssertNil(response.pin)
        XCTAssertEqual(response.token, "secret123")
    }

    // MARK: - AuthResultMessage Tests

    func testAuthResultSuccessEncoding() throws {
        let result = AuthResultMessage.success()
        let data = try JSONEncoder().encode(result)
        let json = try JSONDecoder().decode([String: Any].self, from: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "auth_ok")
        XCTAssertNil(json["reason"])
    }

    func testAuthResultSuccessProperty() {
        let successResult = AuthResultMessage.success()
        XCTAssertTrue(successResult.success)

        let failedResult = AuthResultMessage.failure(reason: "bad")
        XCTAssertFalse(failedResult.success)
    }

    func testAuthResultFailureEncoding() throws {
        let result = AuthResultMessage.failure(reason: "Invalid PIN")
        let data = try JSONEncoder().encode(result)
        let json = try JSONDecoder().decode([String: String].self, from: data)

        XCTAssertEqual(json["type"], "auth_failed")
        XCTAssertEqual(json["reason"], "Invalid PIN")
    }

    func testAuthResultSuccessDecoding() throws {
        let json = """
        {"type":"auth_ok"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(AuthMessage.self, from: data)

        guard case .authResult(let result) = message else {
            XCTFail("Expected auth_result message")
            return
        }

        XCTAssertTrue(result.success)
        XCTAssertNil(result.reason)
    }

    func testAuthResultFailureDecoding() throws {
        let json = """
        {"type":"auth_failed","reason":"Connection rejected"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(AuthMessage.self, from: data)

        guard case .authResult(let result) = message else {
            XCTFail("Expected auth_result message")
            return
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.reason, "Connection rejected")
    }

    // MARK: - AuthMessage Envelope Tests

    func testAuthMessageRoundTrip() throws {
        // Test that all message types can round-trip through encoding/decoding
        let messages: [AuthMessage] = [
            .hello(HelloMessage(app: "Test", subsystem: "com.test")),
            .authChallenge(AuthChallengeMessage(method: .pin(for: .any))),
            .authResponse(AuthResponseMessage(pin: "123456")),
            .authResult(AuthResultMessage.success()),
            .authResult(AuthResultMessage.failure(reason: "Test failure")),
        ]

        for original in messages {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AuthMessage.self, from: data)

            // Verify type matches
            switch (original, decoded) {
            case (.hello, .hello):
                break  // OK
            case (.authChallenge, .authChallenge):
                break  // OK
            case (.authResponse, .authResponse):
                break  // OK
            case (.authResult, .authResult):
                break  // OK
            default:
                XCTFail("Round-trip mismatch: \(original) != \(decoded)")
            }
        }
    }

    func testUnknownMessageTypeThrows() {
        let json = """
        {"type":"unknown_message"}
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AuthMessage.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected dataCorrupted error")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("Unknown message type"))
        }
    }

    func testMissingTypeThrows() {
        let json = """
        {"app":"Test"}
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AuthMessage.self, from: data))
    }

    // MARK: - Message Type Constants

    func testMessageTypeConstants() {
        // Verify message type strings match expected wire format
        XCTAssertEqual(MessageType.hello, "hello")
        XCTAssertEqual(MessageType.authChallenge, "auth_challenge")
        XCTAssertEqual(MessageType.authResponse, "auth_response")
        XCTAssertEqual(MessageType.authOK, "auth_ok")
        XCTAssertEqual(MessageType.authFailed, "auth_failed")
    }

    func testAuthMethodIdentifierConstants() {
        XCTAssertEqual(AuthMethodIdentifier.none, "none")
        XCTAssertEqual(AuthMethodIdentifier.pin, "pin")
        XCTAssertEqual(AuthMethodIdentifier.token, "token")
    }
}

// Helper to decode JSON as dictionary for testing
extension JSONDecoder {
    func decode(_ type: [String: Any].Type, from data: Data) throws -> Any {
        return try JSONSerialization.jsonObject(with: data)
    }
}
