import XCTest
import os
@testable import TimberKit

final class TimberLevelTests: XCTestCase {

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(TimberLevel.trace.rawValue, "trace")
        XCTAssertEqual(TimberLevel.debug.rawValue, "debug")
        XCTAssertEqual(TimberLevel.info.rawValue, "info")
        XCTAssertEqual(TimberLevel.notice.rawValue, "notice")
        XCTAssertEqual(TimberLevel.warning.rawValue, "warning")
        XCTAssertEqual(TimberLevel.error.rawValue, "error")
        XCTAssertEqual(TimberLevel.fault.rawValue, "fault")
    }

    // MARK: - OSLogType Mapping

    func testOSLogTypeMapping() {
        XCTAssertEqual(TimberLevel.trace.osLogType, .debug)
        XCTAssertEqual(TimberLevel.debug.osLogType, .debug)
        XCTAssertEqual(TimberLevel.info.osLogType, .info)
        XCTAssertEqual(TimberLevel.notice.osLogType, .default)
        XCTAssertEqual(TimberLevel.warning.osLogType, .error)
        XCTAssertEqual(TimberLevel.error.osLogType, .error)
        XCTAssertEqual(TimberLevel.fault.osLogType, .fault)
    }

    // MARK: - Comparable

    func testSeverityOrder() {
        XCTAssertLessThan(TimberLevel.trace, .debug)
        XCTAssertLessThan(TimberLevel.debug, .info)
        XCTAssertLessThan(TimberLevel.info, .notice)
        XCTAssertLessThan(TimberLevel.notice, .warning)
        XCTAssertLessThan(TimberLevel.warning, .error)
        XCTAssertLessThan(TimberLevel.error, .fault)
    }

    func testSeverityTransitivity() {
        XCTAssertLessThan(TimberLevel.trace, .fault)
        XCTAssertLessThan(TimberLevel.debug, .error)
        XCTAssertLessThan(TimberLevel.info, .warning)
    }

    func testEqualityForSameLevel() {
        XCTAssertFalse(TimberLevel.info < .info)
        XCTAssertFalse(TimberLevel.info > .info)
        XCTAssertEqual(TimberLevel.info, .info)
    }

    func testGreaterThan() {
        XCTAssertGreaterThan(TimberLevel.fault, .error)
        XCTAssertGreaterThan(TimberLevel.error, .warning)
        XCTAssertGreaterThan(TimberLevel.warning, .notice)
    }

    // MARK: - CaseIterable

    func testAllCases() {
        let allCases = TimberLevel.allCases
        XCTAssertEqual(allCases.count, 7)
        XCTAssertEqual(allCases, [.trace, .debug, .info, .notice, .warning, .error, .fault])
    }

    func testAllCasesAreSorted() {
        let allCases = TimberLevel.allCases
        let sorted = allCases.sorted()
        XCTAssertEqual(allCases, sorted, "allCases should be in severity order")
    }

    // MARK: - Filtering Use Case

    func testMinimumLevelFiltering() {
        let minimumLevel = TimberLevel.warning
        let levelsToStream = TimberLevel.allCases.filter { $0 >= minimumLevel }

        XCTAssertEqual(levelsToStream, [.warning, .error, .fault])
        XCTAssertFalse(levelsToStream.contains(.info))
        XCTAssertFalse(levelsToStream.contains(.debug))
    }
}
