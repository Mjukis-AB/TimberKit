import XCTest
@testable import TimberKit

final class LogEntryTests: XCTestCase {

    // MARK: - Initialization

    func testBasicInitialization() {
        let entry = LogEntry(
            level: .info,
            message: "Test message",
            bundleIdentifier: "com.test.app",
            subsystem: "com.test",
            category: "tests",
            file: "/path/to/File.swift",
            function: "testFunction()",
            line: 42
        )

        XCTAssertEqual(entry.type, "log")
        XCTAssertEqual(entry.level, "info")
        XCTAssertEqual(entry.message, "Test message")
        XCTAssertEqual(entry.bundleIdentifier, "com.test.app")
        XCTAssertEqual(entry.subsystem, "com.test")
        XCTAssertEqual(entry.category, "tests")
        XCTAssertEqual(entry.file, "File.swift")  // Should be basename only
        XCTAssertEqual(entry.function, "testFunction()")
        XCTAssertEqual(entry.line, 42)
    }

    func testFileBasenameExtraction() {
        let entry = LogEntry(
            level: .debug,
            message: "Test",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "/Users/dev/project/Sources/App/Views/ContentView.swift",
            function: "body",
            line: 1
        )

        XCTAssertEqual(entry.file, "ContentView.swift")
    }

    func testTimestampIsPopulated() {
        let before = Date()
        let entry = LogEntry(
            level: .info,
            message: "Test",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "test.swift",
            function: "test()",
            line: 1
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    // MARK: - Bundle Identifier

    func testBundleIdentifierIsIncluded() {
        let entry = LogEntry(
            level: .info,
            message: "Test",
            bundleIdentifier: "com.stripe.Stripe",
            subsystem: "com.stripe.payments",
            category: "checkout",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        XCTAssertEqual(entry.bundleIdentifier, "com.stripe.Stripe")
    }

    func testBundleIdentifierCanBeNil() {
        let entry = LogEntry(
            level: .info,
            message: "Test",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        XCTAssertNil(entry.bundleIdentifier)
    }

    // MARK: - Subsystem and Category

    func testSubsystemAndCategoryAreIncluded() {
        let entry = LogEntry(
            level: .info,
            message: "Test",
            bundleIdentifier: nil,
            subsystem: "com.myapp.networking",
            category: "requests",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        XCTAssertEqual(entry.subsystem, "com.myapp.networking")
        XCTAssertEqual(entry.category, "requests")
    }

    // MARK: - JSON Encoding

    func testJSONEncoding() throws {
        let entry = LogEntry(
            level: .warning,
            message: "Something went wrong",
            bundleIdentifier: "com.test.app",
            subsystem: "com.test",
            category: "errors",
            file: "/path/to/Service.swift",
            function: "handleError()",
            line: 100
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "log")
        XCTAssertEqual(json["level"] as? String, "warning")
        XCTAssertEqual(json["message"] as? String, "Something went wrong")
        XCTAssertEqual(json["bundleIdentifier"] as? String, "com.test.app")
        XCTAssertEqual(json["subsystem"] as? String, "com.test")
        XCTAssertEqual(json["category"] as? String, "errors")
        XCTAssertEqual(json["file"] as? String, "Service.swift")
        XCTAssertEqual(json["function"] as? String, "handleError()")
        XCTAssertEqual(json["line"] as? Int, 100)
        XCTAssertNotNil(json["timestamp"])
    }

    func testJSONEncodingAllLevels() throws {
        let encoder = JSONEncoder()

        for level in TimberLevel.allCases {
            let entry = LogEntry(
                level: level,
                message: "Message",
                bundleIdentifier: nil,
                subsystem: "com.test",
                category: "default",
                file: "test.swift",
                function: "test()",
                line: 1
            )

            let data = try encoder.encode(entry)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            XCTAssertEqual(json["level"] as? String, level.rawValue)
        }
    }

    // MARK: - JSON Decoding (Round-trip)

    func testJSONRoundTrip() throws {
        let original = LogEntry(
            level: .error,
            message: "Error occurred",
            bundleIdentifier: "com.myapp",
            subsystem: "com.myapp",
            category: "main",
            file: "App.swift",
            function: "main()",
            line: 42
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.level, original.level)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.bundleIdentifier, original.bundleIdentifier)
        XCTAssertEqual(decoded.subsystem, original.subsystem)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.file, original.file)
        XCTAssertEqual(decoded.function, original.function)
        XCTAssertEqual(decoded.line, original.line)
        // Timestamps may have slight precision differences, so we compare within a second
        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            original.timestamp.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    // MARK: - LogEntryEncoder

    func testLogEntryEncoderProducesJSONL() throws {
        let entry = LogEntry(
            level: .info,
            message: "Test",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        let data = LogEntryEncoder.shared.encode(entry)
        XCTAssertNotNil(data)

        // Should end with newline (JSONL format)
        XCTAssertEqual(data?.last, 0x0A)

        // Should be valid JSON (without the trailing newline)
        if let data = data {
            let jsonData = data.dropLast()  // Remove newline
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(jsonData)))
        }
    }

    func testLogEntryEncoderUsesISO8601() throws {
        let entry = LogEntry(
            level: .info,
            message: "Test",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        guard let data = LogEntryEncoder.shared.encode(entry),
              let jsonString = String(data: data.dropLast(), encoding: .utf8) else {
            XCTFail("Failed to encode")
            return
        }

        // ISO8601 timestamps contain 'T' separator and typically 'Z' or timezone
        XCTAssertTrue(jsonString.contains("T"), "Timestamp should be ISO8601 format")
    }

    // MARK: - Special Characters

    func testMessageWithSpecialCharacters() throws {
        let entry = LogEntry(
            level: .info,
            message: "Message with \"quotes\" and \\ backslash and emoji 🎉",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(
            json["message"] as? String,
            "Message with \"quotes\" and \\ backslash and emoji 🎉"
        )
    }

    func testMessageWithNewlines() throws {
        let entry = LogEntry(
            level: .debug,
            message: "Line 1\nLine 2\nLine 3",
            bundleIdentifier: nil,
            subsystem: "com.test",
            category: "default",
            file: "test.swift",
            function: "test()",
            line: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded.message, "Line 1\nLine 2\nLine 3")
    }
}
