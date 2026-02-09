import XCTest
import Network
@testable import TimberKit

final class TimberServiceTests: XCTestCase {

    // MARK: - Initialization

    func testBasicInitialization() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let service = TimberService(name: "Test Viewer", endpoint: endpoint)

        XCTAssertEqual(service.name, "Test Viewer")
        XCTAssertTrue(service.metadata.isEmpty)
        XCTAssertNotNil(service.id)
    }

    func testInitializationWithMetadata() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let metadata = ["app": "MyApp", "version": "1.0"]
        let service = TimberService(name: "Test", endpoint: endpoint, metadata: metadata)

        XCTAssertEqual(service.metadata["app"], "MyApp")
        XCTAssertEqual(service.metadata["version"], "1.0")
    }

    // MARK: - Identifiable

    func testUniqueIDs() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let service1 = TimberService(name: "Same Name", endpoint: endpoint)
        let service2 = TimberService(name: "Same Name", endpoint: endpoint)

        XCTAssertNotEqual(service1.id, service2.id)
    }

    // MARK: - Hashable

    func testHashableByNameAndEndpoint() {
        let endpoint1 = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let endpoint2 = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let endpoint3 = NWEndpoint.hostPort(host: "192.168.1.1", port: 9999)

        let service1 = TimberService(name: "Viewer", endpoint: endpoint1)
        let service2 = TimberService(name: "Viewer", endpoint: endpoint2)
        let service3 = TimberService(name: "Viewer", endpoint: endpoint3)
        let service4 = TimberService(name: "Other", endpoint: endpoint1)

        // Same name and equivalent endpoint should have same hash
        XCTAssertEqual(service1.hashValue, service2.hashValue)

        // Different endpoint should have different hash (usually)
        // Note: Hash collisions are possible but unlikely for these values
        XCTAssertNotEqual(service1.hashValue, service3.hashValue)

        // Different name should have different hash
        XCTAssertNotEqual(service1.hashValue, service4.hashValue)
    }

    // MARK: - Equatable

    func testEqualityByNameAndEndpoint() {
        let endpoint1 = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let endpoint2 = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let endpoint3 = NWEndpoint.hostPort(host: "192.168.1.1", port: 9999)

        let service1 = TimberService(name: "Viewer", endpoint: endpoint1)
        let service2 = TimberService(name: "Viewer", endpoint: endpoint2)
        let service3 = TimberService(name: "Viewer", endpoint: endpoint3)
        let service4 = TimberService(name: "Other", endpoint: endpoint1)

        XCTAssertEqual(service1, service2)
        XCTAssertNotEqual(service1, service3)  // Different endpoint
        XCTAssertNotEqual(service1, service4)  // Different name
    }

    func testEqualityIgnoresID() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let service1 = TimberService(name: "Test", endpoint: endpoint)
        let service2 = TimberService(name: "Test", endpoint: endpoint)

        // IDs are different
        XCTAssertNotEqual(service1.id, service2.id)
        // But services are equal (by name and endpoint)
        XCTAssertEqual(service1, service2)
    }

    func testEqualityIgnoresMetadata() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let service1 = TimberService(name: "Test", endpoint: endpoint, metadata: ["key": "value1"])
        let service2 = TimberService(name: "Test", endpoint: endpoint, metadata: ["key": "value2"])

        XCTAssertEqual(service1, service2)
    }

    // MARK: - Set Operations

    func testSetMembership() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let service1 = TimberService(name: "Viewer", endpoint: endpoint)
        let service2 = TimberService(name: "Viewer", endpoint: endpoint)

        var services: Set<TimberService> = [service1]
        services.insert(service2)

        // Should only have one service (duplicates removed)
        XCTAssertEqual(services.count, 1)
    }

    func testSetDifference() {
        let endpoint1 = NWEndpoint.hostPort(host: "127.0.0.1", port: 9999)
        let endpoint2 = NWEndpoint.hostPort(host: "192.168.1.1", port: 9999)

        let oldServices: Set<TimberService> = [
            TimberService(name: "A", endpoint: endpoint1),
            TimberService(name: "B", endpoint: endpoint1)
        ]

        let newServices: Set<TimberService> = [
            TimberService(name: "A", endpoint: endpoint1),  // Still there
            TimberService(name: "C", endpoint: endpoint2)   // New
        ]

        let added = newServices.subtracting(oldServices)
        let removed = oldServices.subtracting(newServices)

        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.name, "C")

        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.name, "B")
    }

    // MARK: - Service Type Constant

    func testServiceTypeConstant() {
        XCTAssertEqual(timberServiceType, "_timber._tcp")
    }
}
