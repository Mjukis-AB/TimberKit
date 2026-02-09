import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The #timber macro transforms a single logging call into two calls:
/// 1. os_log with privacy annotations preserved
/// 2. External streaming with raw values (controlled by Timber.isStreamingEnabled)
///
/// Usage:
///   #timber(.info, "User \(userID, privacy: .private) logged in")
///
/// Expands to:
///   {
///       _timberOSLog.info("User \(userID, privacy: .private) logged in")
///       _timberStreamHandler(.info, "User \(userID) logged in", file: #file, line: #line)
///   }()
///
/// Streaming is controlled at runtime via:
///   - Timber.isStreamingEnabled (default: true in DEBUG, false in RELEASE)
///   - Timber.minimumStreamLevel (default: .trace)
public struct TimberMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // Parse the arguments
        let arguments = node.arguments
        guard arguments.count >= 2 else {
            throw TimberMacroError.invalidArguments
        }

        let args = Array(arguments)

        // First argument: log level
        let levelArg = args[0].expression

        // Second argument: the string interpolation
        let messageArg = args[1].expression

        // Extract the interpolation and create two versions:
        // 1. Original with privacy annotations (for os_log)
        // 2. Stripped version without privacy (for streaming)
        let (osLogMessage, streamMessage) = try parseAndTransformMessage(messageArg)

        // Generate the expansion (runtime check happens in _timberStreamHandler)
        // Pass #dsohandle to identify the calling module's bundle
        let result: ExprSyntax = """
        {
            _timberOSLog.\(raw: levelString(from: levelArg))(\(raw: osLogMessage))
            _timberStreamHandler(\(levelArg), \(raw: streamMessage), dsoHandle: #dsohandle, file: #file, function: #function, line: #line)
        }()
        """

        return result
    }

    private static func levelString(from expr: ExprSyntax) -> String {
        // Handle .info, .debug, etc.
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return "info"
    }

    private static func parseAndTransformMessage(_ expr: ExprSyntax) throws -> (String, String) {
        guard let stringLiteral = expr.as(StringLiteralExprSyntax.self) else {
            // If not a string literal, just use it as-is for both
            let exprText = expr.description
            return (exprText, exprText)
        }

        var osLogParts: [String] = []
        var streamParts: [String] = []

        for segment in stringLiteral.segments {
            switch segment {
            case .stringSegment(let strSegment):
                // Literal text - same for both
                let text = strSegment.content.text
                osLogParts.append(text)
                streamParts.append(text)

            case .expressionSegment(let exprSegment):
                // Interpolated expression - need to handle privacy
                let (osLogExpr, streamExpr) = transformInterpolation(exprSegment)
                osLogParts.append(osLogExpr)
                streamParts.append(streamExpr)
            }
        }

        let osLogMessage = "\"\(osLogParts.joined())\""
        let streamMessage = "\"\(streamParts.joined())\""

        return (osLogMessage, streamMessage)
    }

    private static func transformInterpolation(_ segment: ExpressionSegmentSyntax) -> (String, String) {
        // The expression segment includes \( ... )
        // We need to:
        // 1. Keep the full expression for os_log (with privacy:)
        // 2. Strip the privacy parameter for streaming

        var expressions: [String] = []
        var hasPrivacy = false

        for element in segment.expressions {
            let exprText = element.expression.description.trimmingCharacters(in: .whitespaces)

            // Check if this is a privacy argument
            if let labeled = element.label, labeled.text == "privacy" {
                hasPrivacy = true
                // Skip privacy for stream version
                continue
            }

            expressions.append(exprText)
        }

        let osLogExpr = segment.description // Keep original with privacy
        let streamExpr: String

        if hasPrivacy && !expressions.isEmpty {
            // Create version without privacy
            streamExpr = "\\(\(expressions.joined(separator: ", ")))"
        } else {
            // No privacy annotation, same for both
            streamExpr = segment.description
        }

        return (osLogExpr, streamExpr)
    }
}

enum TimberMacroError: Error, CustomStringConvertible {
    case invalidArguments

    var description: String {
        switch self {
        case .invalidArguments:
            return "#timber requires a log level and message: #timber(.info, \"message\")"
        }
    }
}

@main
struct TimberKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TimberMacro.self,
    ]
}
