import Foundation

/// Generates and validates PIN codes for Timber authentication
public struct PINGenerator: Sendable {
    /// Default PIN length
    public static let defaultLength = 6

    /// Generate a random PIN code
    /// - Parameter length: Number of digits (default: 6)
    /// - Returns: A random numeric PIN string
    public static func generate(length: Int = defaultLength) -> String {
        var pin = ""
        for _ in 0..<length {
            pin += String(Int.random(in: 0...9))
        }
        return pin
    }

    /// Validate a PIN format (must be all digits, correct length)
    public static func isValid(_ pin: String, length: Int = defaultLength) -> Bool {
        guard pin.count == length else { return false }
        return pin.allSatisfy { $0.isNumber }
    }

    /// Compare two PINs in constant time (prevent timing attacks)
    public static func compare(_ pin1: String, _ pin2: String) -> Bool {
        guard pin1.count == pin2.count else { return false }

        var result: UInt8 = 0
        for (c1, c2) in zip(pin1.utf8, pin2.utf8) {
            result |= c1 ^ c2
        }
        return result == 0
    }
}
