import Foundation

/// Configuration for log buffering behavior
public struct BufferingConfiguration: Sendable {
    /// Maximum number of log entries to buffer
    public let maxEntries: Int

    /// What to do when buffer is full
    public let overflowStrategy: OverflowStrategy

    /// Where to store buffered logs
    public let persistence: Persistence

    /// Whether to send buffered logs from previous session on app launch
    public let sendOnLaunch: Bool

    /// How to handle overflow when buffer is full
    public enum OverflowStrategy: Sendable {
        /// Drop oldest entries to make room (FIFO)
        case dropOldest
        /// Drop new entries until space is available
        case dropNewest
        /// Drop lower-severity entries first (trace, debug before error, fault)
        case dropByLevel
    }

    /// Where buffered logs are stored
    public enum Persistence: Sendable {
        /// In-memory only - fast but lost on crash/termination
        case memory
        /// File-backed - survives crashes, slightly slower
        case file
        /// File-backed with custom directory
        case fileAt(URL)
    }

    /// Create a buffering configuration
    /// - Parameters:
    ///   - maxEntries: Maximum entries to buffer (default: 1000)
    ///   - overflowStrategy: What to do when full (default: .dropOldest)
    ///   - persistence: Storage type (default: .file)
    ///   - sendOnLaunch: Send previous session's logs on launch (default: true)
    public init(
        maxEntries: Int = 1000,
        overflowStrategy: OverflowStrategy = .dropOldest,
        persistence: Persistence = .file,
        sendOnLaunch: Bool = true
    ) {
        self.maxEntries = maxEntries
        self.overflowStrategy = overflowStrategy
        self.persistence = persistence
        self.sendOnLaunch = sendOnLaunch
    }

    // MARK: - Presets

    /// Default configuration: 1000 entries, file-backed, drop oldest
    public static let `default` = BufferingConfiguration()

    /// Disabled - no buffering, logs dropped when disconnected
    public static let disabled = BufferingConfiguration(
        maxEntries: 0,
        persistence: .memory,
        sendOnLaunch: false
    )

    /// Memory-only buffering - faster but lost on crash
    public static let memoryOnly = BufferingConfiguration(
        maxEntries: 1000,
        persistence: .memory,
        sendOnLaunch: false
    )

    /// Large buffer for high-volume logging
    public static let large = BufferingConfiguration(
        maxEntries: 10000,
        overflowStrategy: .dropByLevel,
        persistence: .file,
        sendOnLaunch: true
    )

    /// Minimal buffering - small footprint
    public static let minimal = BufferingConfiguration(
        maxEntries: 100,
        overflowStrategy: .dropOldest,
        persistence: .file,
        sendOnLaunch: true
    )

    /// Check if buffering is enabled
    public var isEnabled: Bool {
        maxEntries > 0
    }
}

// MARK: - Internal Helpers

extension BufferingConfiguration {
    /// Get the file URL for buffer storage
    func bufferFileURL(forSubsystem subsystem: String) -> URL? {
        switch persistence {
        case .memory:
            return nil
        case .file:
            return defaultBufferDirectory(forSubsystem: subsystem)
        case .fileAt(let url):
            return url.appendingPathComponent("timber-buffer.jsonl")
        }
    }

    private func defaultBufferDirectory(forSubsystem subsystem: String) -> URL? {
        guard let cachesDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let timberDir = cachesDir
            .appendingPathComponent("Timber", isDirectory: true)
            .appendingPathComponent(subsystem.replacingOccurrences(of: ".", with: "-"), isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: timberDir,
            withIntermediateDirectories: true
        )

        return timberDir.appendingPathComponent("buffer.jsonl")
    }
}
