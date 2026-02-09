import Foundation
import os

/// Log a message to both os_log (with privacy) and external streaming (full content)
///
/// Usage:
/// ```swift
/// #timber(.info, "User \(userID, privacy: .private) logged in")
/// ```
///
/// The macro generates two log calls:
/// 1. `os_log` with privacy annotations preserved (production-safe)
/// 2. External stream with all values visible (controlled by `Timber.isStreamingEnabled`)
///
/// Streaming is controlled at runtime via:
/// - `Timber.isStreamingEnabled` (default: true in DEBUG, false in RELEASE)
/// - `Timber.minimumStreamLevel` (default: .trace)
@freestanding(expression)
public macro timber(_ level: TimberLevel, _ message: OSLogMessage) = #externalMacro(
    module: "TimberKitMacros",
    type: "TimberMacro"
)
