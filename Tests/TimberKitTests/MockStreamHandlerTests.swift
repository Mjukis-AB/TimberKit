import XCTest
@testable import TimberKit

final class MockStreamHandlerTests: XCTestCase {

    // MARK: - Basic Functionality

    func testInitialState() {
        let mock = MockStreamHandler()
        XCTAssertEqual(mock.entryCount, 0)
        XCTAssertTrue(mock.entries.isEmpty)
        XCTAssertFalse(mock.isClosed)
    }

    func testSendRecordsEntry() {
        let mock = MockStreamHandler()

        mock.send(
            level: .info,
            message: "Test message",
            bundleIdentifier: "com.test",
            file: "/path/to/File.swift",
            function: "testFunction()",
            line: 42
        )

        XCTAssertEqual(mock.entryCount, 1)
        XCTAssertEqual(mock.entries[0].level, "info")
        XCTAssertEqual(mock.entries[0].message, "Test message")
        XCTAssertEqual(mock.entries[0].file, "File.swift")
        XCTAssertEqual(mock.entries[0].function, "testFunction()")
        XCTAssertEqual(mock.entries[0].line, 42)
    }

    func testSendMultipleEntries() {
        let mock = MockStreamHandler()

        mock.send(level: .debug, message: "First", bundleIdentifier: nil, file: "a.swift", function: "a()", line: 1)
        mock.send(level: .info, message: "Second", bundleIdentifier: nil, file: "b.swift", function: "b()", line: 2)
        mock.send(level: .error, message: "Third", bundleIdentifier: nil, file: "c.swift", function: "c()", line: 3)

        XCTAssertEqual(mock.entryCount, 3)
        XCTAssertEqual(mock.entries[0].message, "First")
        XCTAssertEqual(mock.entries[1].message, "Second")
        XCTAssertEqual(mock.entries[2].message, "Third")
    }

    // MARK: - Close

    func testCloseSetsClosed() {
        let mock = MockStreamHandler()
        XCTAssertFalse(mock.isClosed)

        mock.close()

        XCTAssertTrue(mock.isClosed)
    }

    func testCloseDoesNotClearEntries() {
        let mock = MockStreamHandler()
        mock.send(level: .info, message: "Test", bundleIdentifier: nil, file: "t.swift", function: "t()", line: 1)

        mock.close()

        XCTAssertEqual(mock.entryCount, 1)
        XCTAssertTrue(mock.isClosed)
    }

    // MARK: - Reset

    func testResetClearsEntries() {
        let mock = MockStreamHandler()
        mock.send(level: .info, message: "Test", bundleIdentifier: nil, file: "t.swift", function: "t()", line: 1)
        mock.close()

        mock.reset()

        XCTAssertEqual(mock.entryCount, 0)
        XCTAssertFalse(mock.isClosed)
    }

    // MARK: - Thread Safety

    func testConcurrentSends() {
        let mock = MockStreamHandler()
        let expectation = XCTestExpectation(description: "All sends complete")
        expectation.expectedFulfillmentCount = 100

        DispatchQueue.concurrentPerform(iterations: 100) { i in
            mock.send(
                level: .info,
                message: "Message \(i)",
                bundleIdentifier: nil,
                file: "test.swift",
                function: "test()",
                line: i
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(mock.entryCount, 100)
    }

    // MARK: - Protocol Conformance

    func testConformsToStreamHandler() {
        let handler: StreamHandler = MockStreamHandler()

        handler.send(level: .warning, message: "Test", bundleIdentifier: nil, file: "f.swift", function: "f()", line: 1)
        handler.close()

        // Should compile and work correctly
        XCTAssertTrue(true)
    }

    // MARK: - Integration with Timber

    func testCanBeUsedAsTimberHandler() {
        let mock = MockStreamHandler()
        let originalHandler = Timber.streamHandler

        // Set as Timber's handler
        Timber.streamHandler = mock

        // Would work with actual macro, but we simulate
        mock.send(level: .info, message: "App started", bundleIdentifier: nil, file: "App.swift", function: "main()", line: 10)

        XCTAssertEqual(mock.entryCount, 1)
        XCTAssertEqual(mock.entries[0].message, "App started")

        // Restore original
        Timber.streamHandler = originalHandler
    }

    // MARK: - Bundle Identifier

    func testBundleIdentifierIsRecorded() {
        let mock = MockStreamHandler()

        mock.send(
            level: .info,
            message: "Test",
            bundleIdentifier: "com.stripe.Stripe",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        XCTAssertEqual(mock.entries[0].bundleIdentifier, "com.stripe.Stripe")
    }
}
