import Foundation
import os

/// Log level for Timber messages
public enum TimberLevel: String, Sendable, Comparable, CaseIterable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    /// Convert to os_log type
    public var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .error
        case .error: return .error
        case .fault: return .fault
        }
    }

    private var severity: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .notice: return 3
        case .warning: return 4
        case .error: return 5
        case .fault: return 6
        }
    }

    public static func < (lhs: TimberLevel, rhs: TimberLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}
