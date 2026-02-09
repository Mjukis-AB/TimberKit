import Foundation
import os

// ============================================================================
// MARK: - Internal Globals for Macro Expansion
// ============================================================================
//
// These are accessed by the macro expansion. The macro generates code like:
//   _timberOSLog.info("...")
//   _timberStreamHandler(.info, "...", file: #file, ...)
//
// Users should not call these directly.

/// Internal: Access to the configured Logger for macro expansion
public var _timberOSLog: Logger {
    Timber.logger
}

/// Internal: Stream handler function called by macro expansion
public func _timberStreamHandler(
    _ level: TimberLevel,
    _ message: String,
    dsoHandle: UnsafeRawPointer,
    file: String,
    function: String,
    line: Int
) {
    // Check if streaming is enabled and level meets minimum
    guard Timber.isStreamingEnabled,
          level >= Timber.minimumStreamLevel else {
        return
    }

    // Resolve bundle identifier from dsoHandle (with configured bundleIdentifier as priority)
    let bundleId = Timber.resolveBundleIdentifier(dsoHandle: dsoHandle)

    Timber.streamHandler.send(
        level: level,
        message: message,
        bundleIdentifier: bundleId,
        file: file,
        function: function,
        line: line
    )
}
