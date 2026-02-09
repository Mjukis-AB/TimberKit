import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(TimberKitMacros)
import TimberKitMacros

final class TimberKitTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        "timber": TimberMacro.self,
    ]

    func testSimpleMessage() throws {
        assertMacroExpansion(
            """
            #timber(.info, "Hello world")
            """,
            expandedSource: """
            {
                _timberOSLog.info("Hello world")
                _timberStreamHandler(.info, "Hello world", dsoHandle: #dsohandle, file: #file, function: #function, line: #line)
            }()
            """,
            macros: testMacros
        )
    }

    func testMessageWithInterpolation() throws {
        assertMacroExpansion(
            """
            let count = 5
            #timber(.debug, "Count is \\(count)")
            """,
            expandedSource: """
            let count = 5
            {
                _timberOSLog.debug("Count is \\(count)")
                _timberStreamHandler(.debug, "Count is \\(count)", dsoHandle: #dsohandle, file: #file, function: #function, line: #line)
            }()
            """,
            macros: testMacros
        )
    }

    func testMessageWithPrivacy() throws {
        // This is the key test - privacy should be preserved for os_log
        // but stripped for streaming
        assertMacroExpansion(
            """
            let userID = 123
            #timber(.info, "User \\(userID, privacy: .private) logged in")
            """,
            expandedSource: """
            let userID = 123
            {
                _timberOSLog.info("User \\(userID, privacy: .private) logged in")
                _timberStreamHandler(.info, "User \\(userID) logged in", dsoHandle: #dsohandle, file: #file, function: #function, line: #line)
            }()
            """,
            macros: testMacros
        )
    }

    func testMultipleInterpolations() throws {
        assertMacroExpansion(
            """
            let name = "Alice"
            let secret = "abc123"
            #timber(.warning, "User \\(name, privacy: .public) has token \\(secret, privacy: .private)")
            """,
            expandedSource: """
            let name = "Alice"
            let secret = "abc123"
            {
                _timberOSLog.warning("User \\(name, privacy: .public) has token \\(secret, privacy: .private)")
                _timberStreamHandler(.warning, "User \\(name) has token \\(secret)", dsoHandle: #dsohandle, file: #file, function: #function, line: #line)
            }()
            """,
            macros: testMacros
        )
    }
}
#endif
