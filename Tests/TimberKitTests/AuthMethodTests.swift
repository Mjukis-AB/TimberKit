import XCTest
@testable import TimberKit

final class ConnectionTypeTests: XCTestCase {

    // MARK: - ConnectionType.any

    func testAnyMatchesEverything() {
        XCTAssertTrue(ConnectionType.any.matches(host: "127.0.0.1"))
        XCTAssertTrue(ConnectionType.any.matches(host: "localhost"))
        XCTAssertTrue(ConnectionType.any.matches(host: "192.168.1.100"))
        XCTAssertTrue(ConnectionType.any.matches(host: "example.com"))
        XCTAssertTrue(ConnectionType.any.matches(host: "::1"))
        XCTAssertTrue(ConnectionType.any.matches(host: "anything", isUSB: true))
    }

    // MARK: - ConnectionType.localhost

    func testLocalhostMatchesLocalAddresses() {
        XCTAssertTrue(ConnectionType.localhost.matches(host: "127.0.0.1"))
        XCTAssertTrue(ConnectionType.localhost.matches(host: "localhost"))
        XCTAssertTrue(ConnectionType.localhost.matches(host: "::1"))
    }

    func testLocalhostDoesNotMatchRemote() {
        XCTAssertFalse(ConnectionType.localhost.matches(host: "192.168.1.100"))
        XCTAssertFalse(ConnectionType.localhost.matches(host: "example.com"))
        XCTAssertFalse(ConnectionType.localhost.matches(host: "10.0.0.1"))
    }

    func testLocalhostDoesNotMatchUSB() {
        // USB with non-localhost host should not match localhost type
        XCTAssertFalse(ConnectionType.localhost.matches(host: "169.254.1.1", isUSB: true))
    }

    // MARK: - ConnectionType.usb

    func testUSBMatchesWhenFlagSet() {
        XCTAssertTrue(ConnectionType.usb.matches(host: "169.254.1.1", isUSB: true))
        XCTAssertTrue(ConnectionType.usb.matches(host: "any-host", isUSB: true))
    }

    func testUSBDoesNotMatchWithoutFlag() {
        XCTAssertFalse(ConnectionType.usb.matches(host: "127.0.0.1", isUSB: false))
        XCTAssertFalse(ConnectionType.usb.matches(host: "localhost"))
    }

    // MARK: - ConnectionType.local

    func testLocalMatchesLocalhostOrUSB() {
        XCTAssertTrue(ConnectionType.local.matches(host: "127.0.0.1"))
        XCTAssertTrue(ConnectionType.local.matches(host: "localhost"))
        XCTAssertTrue(ConnectionType.local.matches(host: "::1"))
        XCTAssertTrue(ConnectionType.local.matches(host: "169.254.1.1", isUSB: true))
    }

    func testLocalDoesNotMatchRemote() {
        XCTAssertFalse(ConnectionType.local.matches(host: "192.168.1.100"))
        XCTAssertFalse(ConnectionType.local.matches(host: "example.com"))
    }

    // MARK: - ConnectionType.remote

    func testRemoteMatchesNonLocal() {
        XCTAssertTrue(ConnectionType.remote.matches(host: "192.168.1.100"))
        XCTAssertTrue(ConnectionType.remote.matches(host: "example.com"))
        XCTAssertTrue(ConnectionType.remote.matches(host: "10.0.0.1"))
    }

    func testRemoteDoesNotMatchLocal() {
        XCTAssertFalse(ConnectionType.remote.matches(host: "127.0.0.1"))
        XCTAssertFalse(ConnectionType.remote.matches(host: "localhost"))
        XCTAssertFalse(ConnectionType.remote.matches(host: "::1"))
        XCTAssertFalse(ConnectionType.remote.matches(host: "169.254.1.1", isUSB: true))
    }
}

final class AuthMethodTests: XCTestCase {

    // MARK: - Connection Type

    func testConnectionTypeExtraction() {
        XCTAssertTrue(AuthMethod.none(for: .localhost).connectionType == .localhost)
        XCTAssertTrue(AuthMethod.pin(for: .remote).connectionType == .remote)
        XCTAssertTrue(AuthMethod.token("secret", for: .any).connectionType == .any)
    }

    // MARK: - requiresAuth

    func testNoneDoesNotRequireAuth() {
        let method = AuthMethod.none(for: .any)
        XCTAssertFalse(method.requiresAuth(for: "127.0.0.1"))
        XCTAssertFalse(method.requiresAuth(for: "192.168.1.100"))
    }

    func testPinRequiresAuthWhenMatches() {
        let method = AuthMethod.pin(for: .remote)
        XCTAssertTrue(method.requiresAuth(for: "192.168.1.100"))
        XCTAssertFalse(method.requiresAuth(for: "127.0.0.1"))  // Doesn't match remote
    }

    func testTokenRequiresAuthWhenMatches() {
        let method = AuthMethod.token("secret", for: .any)
        XCTAssertTrue(method.requiresAuth(for: "127.0.0.1"))
        XCTAssertTrue(method.requiresAuth(for: "192.168.1.100"))
    }

    func testPinForLocalDoesNotRequireAuthForRemote() {
        let method = AuthMethod.pin(for: .local)
        XCTAssertTrue(method.requiresAuth(for: "127.0.0.1"))  // Matches local
        XCTAssertFalse(method.requiresAuth(for: "192.168.1.100"))  // Doesn't match local
    }
}

final class AuthConfigurationTests: XCTestCase {

    // MARK: - Default Configuration

    func testDefaultNoAuthForLocal() {
        let config = AuthConfiguration.default
        guard let method = config.requiredAuth(for: "127.0.0.1") else {
            XCTFail("Expected a method for localhost")
            return
        }
        if case .none = method {
            // Expected
        } else {
            XCTFail("Expected .none for localhost, got \(method)")
        }
    }

    func testDefaultPinForRemote() {
        let config = AuthConfiguration.default
        guard let method = config.requiredAuth(for: "192.168.1.100") else {
            XCTFail("Expected a method for remote")
            return
        }
        if case .pin = method {
            // Expected
        } else {
            XCTFail("Expected .pin for remote, got \(method)")
        }
    }

    // MARK: - Preset Configurations

    func testNoneConfiguration() {
        let config = AuthConfiguration.none
        guard let method = config.requiredAuth(for: "192.168.1.100") else {
            XCTFail("Expected a method")
            return
        }
        if case .none = method {
            // Expected
        } else {
            XCTFail("Expected .none, got \(method)")
        }
    }

    func testPinRequiredConfiguration() {
        let config = AuthConfiguration.pinRequired

        guard let localMethod = config.requiredAuth(for: "127.0.0.1") else {
            XCTFail("Expected a method for localhost")
            return
        }
        if case .pin = localMethod {
            // Expected
        } else {
            XCTFail("Expected .pin for localhost")
        }

        guard let remoteMethod = config.requiredAuth(for: "192.168.1.100") else {
            XCTFail("Expected a method for remote")
            return
        }
        if case .pin = remoteMethod {
            // Expected
        } else {
            XCTFail("Expected .pin for remote")
        }
    }

    // MARK: - Custom Configuration

    func testCustomConfigurationPriority() {
        // First matching rule wins
        let config = AuthConfiguration(methods: [
            .none(for: .localhost),
            .pin(for: .local),  // This should never match for localhost because .none matches first
            .token("secret", for: .remote)
        ])

        // Localhost should get .none (first match)
        guard let localhostMethod = config.requiredAuth(for: "127.0.0.1") else {
            XCTFail("Expected a method for localhost")
            return
        }
        if case .none = localhostMethod {
            // Expected
        } else {
            XCTFail("Expected .none for localhost")
        }

        // Remote should get .token
        guard let remoteMethod = config.requiredAuth(for: "192.168.1.100") else {
            XCTFail("Expected a method for remote")
            return
        }
        if case .token = remoteMethod {
            // Expected
        } else {
            XCTFail("Expected .token for remote")
        }
    }

    func testNoMatchingMethod() {
        let config = AuthConfiguration(methods: [
            .pin(for: .localhost)  // Only matches localhost
        ])

        // Remote has no matching method
        XCTAssertNil(config.requiredAuth(for: "192.168.1.100"))
    }

    func testUSBConnection() {
        let config = AuthConfiguration(methods: [
            .none(for: .usb),
            .pin(for: .any)
        ])

        // USB connection should get .none
        guard let usbMethod = config.requiredAuth(for: "169.254.1.1", isUSB: true) else {
            XCTFail("Expected a method for USB")
            return
        }
        if case .none = usbMethod {
            // Expected
        } else {
            XCTFail("Expected .none for USB")
        }

        // Non-USB should get .pin
        guard let nonUSBMethod = config.requiredAuth(for: "169.254.1.1", isUSB: false) else {
            XCTFail("Expected a method for non-USB")
            return
        }
        if case .pin = nonUSBMethod {
            // Expected
        } else {
            XCTFail("Expected .pin for non-USB")
        }
    }
}
