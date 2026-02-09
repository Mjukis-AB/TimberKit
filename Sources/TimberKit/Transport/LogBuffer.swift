import Foundation

/// Protocol for log buffer storage
protocol LogBuffer: Sendable {
    /// Append an entry to the buffer
    func append(_ entry: LogEntry)

    /// Get all buffered entries and clear the buffer
    func drainAll() -> [LogEntry]

    /// Number of entries currently buffered
    var count: Int { get }

    /// Whether the buffer is empty
    var isEmpty: Bool { get }
}

// MARK: - In-Memory Ring Buffer

/// Thread-safe in-memory ring buffer
final class MemoryLogBuffer: LogBuffer, @unchecked Sendable {
    private var buffer: [LogEntry?]
    private var readIndex = 0
    private var writeIndex = 0
    private var _count = 0
    private let capacity: Int
    private let overflowStrategy: BufferingConfiguration.OverflowStrategy
    private let lock = NSLock()

    init(capacity: Int, overflowStrategy: BufferingConfiguration.OverflowStrategy) {
        self.capacity = max(1, capacity)
        self.overflowStrategy = overflowStrategy
        self.buffer = Array(repeating: nil, count: self.capacity)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    var isEmpty: Bool {
        count == 0
    }

    func append(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }

        if _count < capacity {
            // Buffer has space
            buffer[writeIndex] = entry
            writeIndex = (writeIndex + 1) % capacity
            _count += 1
        } else {
            // Buffer is full - apply overflow strategy
            switch overflowStrategy {
            case .dropOldest:
                // Overwrite oldest entry
                buffer[writeIndex] = entry
                writeIndex = (writeIndex + 1) % capacity
                readIndex = (readIndex + 1) % capacity
                // count stays the same

            case .dropNewest:
                // Just drop the new entry
                break

            case .dropByLevel:
                // Find and replace lowest severity entry
                if let indexToReplace = findLowestSeverityIndex(excluding: entry) {
                    buffer[indexToReplace] = entry
                }
            }
        }
    }

    func drainAll() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        var result: [LogEntry] = []
        result.reserveCapacity(_count)

        for i in 0..<_count {
            let index = (readIndex + i) % capacity
            if let entry = buffer[index] {
                result.append(entry)
                buffer[index] = nil
            }
        }

        readIndex = 0
        writeIndex = 0
        _count = 0

        return result
    }

    /// Find the index of the lowest severity entry that's lower than the new entry
    private func findLowestSeverityIndex(excluding newEntry: LogEntry) -> Int? {
        let newSeverity = severityOrder(newEntry.level)

        var lowestIndex: Int?
        var lowestSeverity = Int.max

        for i in 0..<_count {
            let index = (readIndex + i) % capacity
            if let entry = buffer[index] {
                let severity = severityOrder(entry.level)
                if severity < lowestSeverity && severity < newSeverity {
                    lowestSeverity = severity
                    lowestIndex = index
                }
            }
        }

        return lowestIndex
    }

    private func severityOrder(_ level: String) -> Int {
        switch level {
        case "trace": return 0
        case "debug": return 1
        case "info": return 2
        case "notice": return 3
        case "warning": return 4
        case "error": return 5
        case "fault": return 6
        default: return 2
        }
    }
}

// MARK: - File-Backed Buffer

/// Thread-safe file-backed buffer that survives crashes
final class FileLogBuffer: LogBuffer, @unchecked Sendable {
    private let fileURL: URL
    private let capacity: Int
    private let overflowStrategy: BufferingConfiguration.OverflowStrategy
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// In-memory cache of entry count (avoid reading file constantly)
    private var _cachedCount: Int = 0
    private var _countNeedsRefresh = true

    init(
        fileURL: URL,
        capacity: Int,
        overflowStrategy: BufferingConfiguration.OverflowStrategy
    ) {
        self.fileURL = fileURL
        self.capacity = max(1, capacity)
        self.overflowStrategy = overflowStrategy

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // Ensure directory exists
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }

        if _countNeedsRefresh {
            _cachedCount = countLines()
            _countNeedsRefresh = false
        }
        return _cachedCount
    }

    var isEmpty: Bool {
        count == 0
    }

    func append(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }

        // Encode entry to JSON line
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else {
            TimberDiagnostics.reportEncodingFailed(message: entry.message)
            return
        }
        line += "\n"

        // Ensure we have an accurate count before checking overflow
        if _countNeedsRefresh {
            _cachedCount = countLines()
            _countNeedsRefresh = false
        }

        // Check if we need to handle overflow first
        if _cachedCount >= capacity {
            let shouldAppend = handleOverflow(newEntry: entry)
            if !shouldAppend {
                return // Drop the new entry
            }
        }

        // Append to file
        appendToFile(line)
        _cachedCount += 1
    }

    func drainAll() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }

        let entries = readAllEntries()

        // Clear the file
        try? FileManager.default.removeItem(at: fileURL)
        _cachedCount = 0
        _countNeedsRefresh = false

        return entries
    }

    // MARK: - Private Helpers

    private func appendToFile(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Append to existing file
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            // Create new file
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func readAllEntries() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var entries: [LogEntry] = []
        let lines = content.components(separatedBy: "\n")

        for line in lines where !line.isEmpty {
            if let lineData = line.data(using: .utf8),
               let entry = try? decoder.decode(LogEntry.self, from: lineData) {
                entries.append(entry)
            }
        }

        return entries
    }

    private func countLines() -> Int {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    /// Handle overflow when buffer is full
    /// - Returns: true if the new entry should be appended, false if it should be dropped
    private func handleOverflow(newEntry: LogEntry) -> Bool {
        switch overflowStrategy {
        case .dropOldest:
            // Remove first line from file to make room
            removeFirstLine()
            _cachedCount = max(0, _cachedCount - 1)
            return true // Append the new entry

        case .dropNewest:
            // Drop the new entry
            return false

        case .dropByLevel:
            // Read all, try to find a lower-severity entry to remove
            var entries = readAllEntries()
            if let indexToRemove = findLowestSeverityIndex(in: entries, excluding: newEntry) {
                entries.remove(at: indexToRemove)
                rewriteFile(with: entries)
                _cachedCount = entries.count
                return true // Append the new entry
            } else {
                // No lower-severity entry found, drop the new entry
                return false
            }
        }
    }

    private func removeFirstLine() {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        var lines = content.components(separatedBy: "\n")
        if !lines.isEmpty {
            lines.removeFirst()
            let newContent = lines.joined(separator: "\n")
            try? newContent.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }
    }

    private func rewriteFile(with entries: [LogEntry]) {
        var content = ""
        for entry in entries {
            if let data = try? encoder.encode(entry),
               let line = String(data: data, encoding: .utf8) {
                content += line + "\n"
            }
        }
        try? content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    private func findLowestSeverityIndex(in entries: [LogEntry], excluding newEntry: LogEntry) -> Int? {
        let newSeverity = severityOrder(newEntry.level)

        var lowestIndex: Int?
        var lowestSeverity = Int.max

        for (index, entry) in entries.enumerated() {
            let severity = severityOrder(entry.level)
            if severity < lowestSeverity && severity < newSeverity {
                lowestSeverity = severity
                lowestIndex = index
            }
        }

        return lowestIndex
    }

    private func severityOrder(_ level: String) -> Int {
        switch level {
        case "trace": return 0
        case "debug": return 1
        case "info": return 2
        case "notice": return 3
        case "warning": return 4
        case "error": return 5
        case "fault": return 6
        default: return 2
        }
    }
}

// MARK: - Factory

extension LogBuffer where Self == MemoryLogBuffer {
    static func memory(
        capacity: Int,
        overflowStrategy: BufferingConfiguration.OverflowStrategy
    ) -> MemoryLogBuffer {
        MemoryLogBuffer(capacity: capacity, overflowStrategy: overflowStrategy)
    }
}

extension LogBuffer where Self == FileLogBuffer {
    static func file(
        at url: URL,
        capacity: Int,
        overflowStrategy: BufferingConfiguration.OverflowStrategy
    ) -> FileLogBuffer {
        FileLogBuffer(fileURL: url, capacity: capacity, overflowStrategy: overflowStrategy)
    }
}
