import XCTest
@testable import TimberKit

// MARK: - BufferingConfiguration Tests

final class BufferingConfigurationTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultConfiguration() {
        let config = BufferingConfiguration.default

        XCTAssertEqual(config.maxEntries, 1000)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.sendOnLaunch)
    }

    func testDisabledConfiguration() {
        let config = BufferingConfiguration.disabled

        XCTAssertEqual(config.maxEntries, 0)
        XCTAssertFalse(config.isEnabled)
        XCTAssertFalse(config.sendOnLaunch)
    }

    func testMemoryOnlyConfiguration() {
        let config = BufferingConfiguration.memoryOnly

        XCTAssertEqual(config.maxEntries, 1000)
        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.sendOnLaunch) // Memory doesn't survive crash
    }

    func testLargeConfiguration() {
        let config = BufferingConfiguration.large

        XCTAssertEqual(config.maxEntries, 10000)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.sendOnLaunch)
    }

    func testMinimalConfiguration() {
        let config = BufferingConfiguration.minimal

        XCTAssertEqual(config.maxEntries, 100)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.sendOnLaunch)
    }

    func testCustomConfiguration() {
        let config = BufferingConfiguration(
            maxEntries: 500,
            overflowStrategy: .dropNewest,
            persistence: .memory,
            sendOnLaunch: false
        )

        XCTAssertEqual(config.maxEntries, 500)
        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.sendOnLaunch)
    }

    func testIsEnabledWhenMaxEntriesIsZero() {
        let config = BufferingConfiguration(maxEntries: 0)
        XCTAssertFalse(config.isEnabled)
    }

    func testIsEnabledWhenMaxEntriesIsPositive() {
        let config = BufferingConfiguration(maxEntries: 1)
        XCTAssertTrue(config.isEnabled)
    }
}

// MARK: - MemoryLogBuffer Tests

final class MemoryLogBufferTests: XCTestCase {

    func testEmptyBuffer() {
        let buffer = MemoryLogBuffer(capacity: 10, overflowStrategy: .dropOldest)

        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testAppendAndCount() {
        let buffer = MemoryLogBuffer(capacity: 10, overflowStrategy: .dropOldest)
        let entry = makeEntry(message: "Test")

        buffer.append(entry)

        XCTAssertEqual(buffer.count, 1)
        XCTAssertFalse(buffer.isEmpty)
    }

    func testDrainAll() {
        let buffer = MemoryLogBuffer(capacity: 10, overflowStrategy: .dropOldest)
        buffer.append(makeEntry(message: "First"))
        buffer.append(makeEntry(message: "Second"))
        buffer.append(makeEntry(message: "Third"))

        let entries = buffer.drainAll()

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].message, "First")
        XCTAssertEqual(entries[1].message, "Second")
        XCTAssertEqual(entries[2].message, "Third")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDropOldestOverflow() {
        let buffer = MemoryLogBuffer(capacity: 3, overflowStrategy: .dropOldest)

        buffer.append(makeEntry(message: "1"))
        buffer.append(makeEntry(message: "2"))
        buffer.append(makeEntry(message: "3"))
        buffer.append(makeEntry(message: "4")) // Overflow

        XCTAssertEqual(buffer.count, 3)
        let entries = buffer.drainAll()
        XCTAssertEqual(entries.map { $0.message }, ["2", "3", "4"])
    }

    func testDropNewestOverflow() {
        let buffer = MemoryLogBuffer(capacity: 3, overflowStrategy: .dropNewest)

        buffer.append(makeEntry(message: "1"))
        buffer.append(makeEntry(message: "2"))
        buffer.append(makeEntry(message: "3"))
        buffer.append(makeEntry(message: "4")) // Should be dropped

        XCTAssertEqual(buffer.count, 3)
        let entries = buffer.drainAll()
        XCTAssertEqual(entries.map { $0.message }, ["1", "2", "3"])
    }

    func testDropByLevelOverflow() {
        let buffer = MemoryLogBuffer(capacity: 3, overflowStrategy: .dropByLevel)

        buffer.append(makeEntry(message: "debug", level: .debug))
        buffer.append(makeEntry(message: "info", level: .info))
        buffer.append(makeEntry(message: "error", level: .error))
        buffer.append(makeEntry(message: "warning", level: .warning)) // Should replace debug

        XCTAssertEqual(buffer.count, 3)
        let entries = buffer.drainAll()
        let messages = entries.map { $0.message }
        XCTAssertFalse(messages.contains("debug")) // Debug was dropped
        XCTAssertTrue(messages.contains("warning")) // Warning was added
    }

    func testDropByLevelKeepsHigherSeverity() {
        let buffer = MemoryLogBuffer(capacity: 2, overflowStrategy: .dropByLevel)

        buffer.append(makeEntry(message: "error1", level: .error))
        buffer.append(makeEntry(message: "fault1", level: .fault))
        buffer.append(makeEntry(message: "debug", level: .debug)) // Lower severity, should be dropped

        XCTAssertEqual(buffer.count, 2)
        let entries = buffer.drainAll()
        let levels = entries.map { $0.level }
        XCTAssertTrue(levels.contains("error"))
        XCTAssertTrue(levels.contains("fault"))
    }

    func testConcurrentAccess() {
        let buffer = MemoryLogBuffer(capacity: 100, overflowStrategy: .dropOldest)
        let expectation = XCTestExpectation(description: "Concurrent appends")
        expectation.expectedFulfillmentCount = 50

        DispatchQueue.concurrentPerform(iterations: 50) { i in
            buffer.append(makeEntry(message: "Message \(i)"))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(buffer.count, 50)
    }

    // MARK: - Helpers

    private func makeEntry(message: String, level: TimberLevel = .info) -> LogEntry {
        LogEntry(
            level: level,
            message: message,
            bundleIdentifier: "com.test",
            subsystem: "test",
            category: "test",
            file: "Test.swift",
            function: "test()",
            line: 1
        )
    }
}

// MARK: - FileLogBuffer Tests

final class FileLogBufferTests: XCTestCase {

    var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempFileURL = tempDir.appendingPathComponent("timber-test-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testEmptyBuffer() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 10,
            overflowStrategy: .dropOldest
        )

        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testAppendCreatesFile() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 10,
            overflowStrategy: .dropOldest
        )
        let entry = makeEntry(message: "Test")

        buffer.append(entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testAppendAndDrain() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 10,
            overflowStrategy: .dropOldest
        )

        buffer.append(makeEntry(message: "First"))
        buffer.append(makeEntry(message: "Second"))

        let entries = buffer.drainAll()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].message, "First")
        XCTAssertEqual(entries[1].message, "Second")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDrainRemovesFile() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 10,
            overflowStrategy: .dropOldest
        )
        buffer.append(makeEntry(message: "Test"))

        _ = buffer.drainAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testDropOldestOverflow() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 3,
            overflowStrategy: .dropOldest
        )

        buffer.append(makeEntry(message: "1"))
        buffer.append(makeEntry(message: "2"))
        buffer.append(makeEntry(message: "3"))
        buffer.append(makeEntry(message: "4")) // Overflow

        let entries = buffer.drainAll()
        XCTAssertEqual(entries.map { $0.message }, ["2", "3", "4"])
    }

    func testDropNewestOverflow() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 3,
            overflowStrategy: .dropNewest
        )

        buffer.append(makeEntry(message: "1"))
        buffer.append(makeEntry(message: "2"))
        buffer.append(makeEntry(message: "3"))
        buffer.append(makeEntry(message: "4")) // Should be dropped

        XCTAssertEqual(buffer.count, 3)
        let entries = buffer.drainAll()
        XCTAssertEqual(entries.map { $0.message }, ["1", "2", "3"])
    }

    func testDropByLevelOverflow() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 3,
            overflowStrategy: .dropByLevel
        )

        buffer.append(makeEntry(message: "debug", level: .debug))
        buffer.append(makeEntry(message: "info", level: .info))
        buffer.append(makeEntry(message: "error", level: .error))
        buffer.append(makeEntry(message: "warning", level: .warning)) // Should replace debug

        XCTAssertEqual(buffer.count, 3)
        let entries = buffer.drainAll()
        let messages = entries.map { $0.message }
        XCTAssertFalse(messages.contains("debug")) // Debug was dropped
        XCTAssertTrue(messages.contains("warning")) // Warning was added
    }

    func testDropByLevelKeepsHigherSeverity() {
        let buffer = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 2,
            overflowStrategy: .dropByLevel
        )

        buffer.append(makeEntry(message: "error1", level: .error))
        buffer.append(makeEntry(message: "fault1", level: .fault))
        buffer.append(makeEntry(message: "debug", level: .debug)) // Lower severity, should be dropped

        XCTAssertEqual(buffer.count, 2)
        let entries = buffer.drainAll()
        let levels = entries.map { $0.level }
        XCTAssertTrue(levels.contains("error"))
        XCTAssertTrue(levels.contains("fault"))
        XCTAssertFalse(entries.map { $0.message }.contains("debug"))
    }

    func testPersistenceAcrossInstances() {
        // Write with first instance
        let buffer1 = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 10,
            overflowStrategy: .dropOldest
        )
        buffer1.append(makeEntry(message: "Persisted"))

        // Read with second instance (simulating crash recovery)
        let buffer2 = FileLogBuffer(
            fileURL: tempFileURL,
            capacity: 10,
            overflowStrategy: .dropOldest
        )
        let entries = buffer2.drainAll()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].message, "Persisted")
    }

    // MARK: - Helpers

    private func makeEntry(message: String, level: TimberLevel = .info) -> LogEntry {
        LogEntry(
            level: level,
            message: message,
            bundleIdentifier: "com.test",
            subsystem: "test",
            category: "test",
            file: "Test.swift",
            function: "test()",
            line: 1
        )
    }
}

// MARK: - BufferingStreamHandler Tests

final class BufferingStreamHandlerTests: XCTestCase {

    func testBuffersWhenDisconnected() {
        let mock = MockStreamHandler()
        let handler = BufferingStreamHandler(
            wrapping: mock,
            configuration: .memoryOnly,
            subsystem: "test"
        )

        // Simulate disconnection
        handler.connectionLost()

        // Send logs
        handler.send(
            level: .info,
            message: "Buffered message",
            bundleIdentifier: nil,
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        // Give async queue time to process
        Thread.sleep(forTimeInterval: 0.1)

        // Mock should NOT have received the message
        XCTAssertEqual(mock.entryCount, 0)
    }

    func testFlushesOnReconnect() {
        let mock = MockStreamHandler()
        let handler = BufferingStreamHandler(
            wrapping: mock,
            configuration: .memoryOnly,
            subsystem: "test"
        )

        // Start disconnected
        handler.connectionLost()

        // Send while disconnected
        handler.send(
            level: .info,
            message: "Buffered",
            bundleIdentifier: nil,
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(mock.entryCount, 0)

        // Reconnect
        handler.connectionEstablished()

        // Give async queue time to flush
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(mock.entryCount, 1)
        XCTAssertEqual(mock.entries[0].message, "Buffered")
    }

    func testSendsDirectlyWhenConnected() {
        let mock = MockStreamHandler()
        let handler = BufferingStreamHandler(
            wrapping: mock,
            configuration: .memoryOnly,
            subsystem: "test"
        )

        // Ensure connected
        handler.connectionEstablished()

        handler.send(
            level: .info,
            message: "Direct",
            bundleIdentifier: nil,
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        // Give async queue time to process
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertEqual(mock.entryCount, 1)
        XCTAssertEqual(mock.entries[0].message, "Direct")
    }

    func testDisabledBufferingDropsLogsWhenDisconnected() {
        let mock = MockStreamHandler()
        let handler = BufferingStreamHandler(
            wrapping: mock,
            configuration: .disabled,
            subsystem: "test"
        )

        handler.connectionLost()

        handler.send(
            level: .info,
            message: "Dropped",
            bundleIdentifier: nil,
            file: "Test.swift",
            function: "test()",
            line: 1
        )

        Thread.sleep(forTimeInterval: 0.1)

        handler.connectionEstablished()
        Thread.sleep(forTimeInterval: 0.1)

        // Log was dropped, not buffered
        XCTAssertEqual(mock.entryCount, 0)
    }

    func testConnectionStateCallback() {
        let mock = MockStreamHandler()
        let handler = BufferingStreamHandler(
            wrapping: mock,
            configuration: .memoryOnly,
            subsystem: "test"
        )

        var states: [Bool] = []
        handler.onConnectionStateChanged = { isConnected in
            states.append(isConnected)
        }

        handler.connectionLost()
        handler.connectionEstablished()
        handler.connectionLost()

        XCTAssertEqual(states, [false, true, false])
    }

    func testCloseClosesWrappedHandler() {
        let mock = MockStreamHandler()
        let handler = BufferingStreamHandler(
            wrapping: mock,
            configuration: .memoryOnly,
            subsystem: "test"
        )

        handler.close()

        XCTAssertTrue(mock.isClosed)
    }

    func testConvenienceInitializerTCP() throws {
        // This tests that the static factory method compiles and works
        // (won't actually connect in a test environment)
        do {
            _ = try BufferingStreamHandler.tcp(
                host: "127.0.0.1",
                port: 9999,
                buffering: .memoryOnly,
                subsystem: "test"
            )
        } catch {
            // Expected to fail connecting, but should not crash
        }
    }
}

// MARK: - Integration with Timber

final class TimberBufferingIntegrationTests: XCTestCase {

    var originalHandler: StreamHandler!

    override func setUp() {
        super.setUp()
        originalHandler = Timber.streamHandler
    }

    override func tearDown() {
        Timber.streamHandler = originalHandler
        super.tearDown()
    }

    func testConfigureWithBuffering() {
        let mock = MockStreamHandler()

        Timber.configure(
            subsystem: "com.test",
            category: "test",
            handler: mock,
            buffering: .memoryOnly
        )

        XCTAssertNotNil(Timber.bufferingHandler)
    }

    func testConfigureWithDisabledBuffering() {
        let mock = MockStreamHandler()

        Timber.configure(
            subsystem: "com.test",
            category: "test",
            handler: mock,
            buffering: .disabled
        )

        XCTAssertNil(Timber.bufferingHandler)
    }

    func testSendBufferedLogsNoOpWhenNotBuffering() {
        let mock = MockStreamHandler()
        Timber.streamHandler = mock

        // Should not crash
        Timber.sendBufferedLogs()
    }
}
