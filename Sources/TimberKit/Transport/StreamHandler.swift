import Foundation
import Network

/// Protocol for handling log streaming to external viewers
public protocol StreamHandler: Sendable {
    /// Send a log entry to the viewer
    func send(
        level: TimberLevel,
        message: String,
        bundleIdentifier: String?,
        file: String,
        function: String,
        line: Int
    )

    /// Close the connection
    func close()
}

// MARK: - Mock Support

/// A mock stream handler for testing
/// Records all sent log entries for verification
public final class MockStreamHandler: StreamHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    private var _closed = false

    /// All entries that have been sent
    public var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    /// Whether close() was called
    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _closed
    }

    /// Number of entries sent
    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _entries.count
    }

    public init() {}

    public func send(
        level: TimberLevel,
        message: String,
        bundleIdentifier: String?,
        file: String,
        function: String,
        line: Int
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            bundleIdentifier: bundleIdentifier,
            subsystem: Timber.subsystem,
            category: Timber.category,
            file: file,
            function: function,
            line: line
        )
        lock.lock()
        _entries.append(entry)
        lock.unlock()
    }

    public func close() {
        lock.lock()
        _closed = true
        lock.unlock()
    }

    /// Clear all recorded entries (for test reset)
    public func reset() {
        lock.lock()
        _entries.removeAll()
        _closed = false
        lock.unlock()
    }
}

// MARK: - Shared Infrastructure

/// Thread-safe JSON encoder configured for Timber wire protocol
final class LogEntryEncoder: @unchecked Sendable {
    static let shared = LogEntryEncoder()

    private let encoder: JSONEncoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func encode(_ entry: LogEntry) -> Data? {
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(Constants.jsonlTerminator)
        return data
    }
}

/// Creates a validated NWEndpoint from host and port
/// - Throws: TimberError.invalidConfiguration if port is invalid
func makeEndpoint(host: String, port: UInt16) throws -> NWEndpoint {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        throw TimberError.invalidConfiguration(reason: "Invalid port: \(port)")
    }
    return NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
}

/// A log entry sent over the wire
public struct LogEntry: Codable, Sendable {
    public let type: String
    public let timestamp: Date
    public let bundleIdentifier: String?
    public let subsystem: String
    public let category: String
    public let level: String
    public let message: String
    public let file: String
    public let function: String
    public let line: Int

    public init(
        level: TimberLevel,
        message: String,
        bundleIdentifier: String?,
        subsystem: String,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        self.type = MessageType.log
        self.timestamp = Date()
        self.bundleIdentifier = bundleIdentifier
        self.subsystem = subsystem
        self.category = category
        self.level = level.rawValue
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
    }
}

/// Default handler that prints to console (useful for debugging)
public struct ConsoleStreamHandler: StreamHandler, Sendable {
    public init() {}

    public func send(
        level: TimberLevel,
        message: String,
        bundleIdentifier: String?,
        file: String,
        function: String,
        line: Int
    ) {
        let filename = (file as NSString).lastPathComponent
        let bundlePrefix = bundleIdentifier.map { "[\($0)] " } ?? ""
        print("📡 \(bundlePrefix)[\(level.rawValue.uppercased())] \(filename):\(line) - \(message)")
    }

    public func close() {
        // No-op for console
    }
}
