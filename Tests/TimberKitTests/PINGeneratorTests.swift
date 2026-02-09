import XCTest
@testable import TimberKit

final class PINGeneratorTests: XCTestCase {

    // MARK: - Generation Tests

    func testGenerateDefaultLength() {
        let pin = PINGenerator.generate()
        XCTAssertEqual(pin.count, 6)
        XCTAssertTrue(pin.allSatisfy { $0.isNumber })
    }

    func testGenerateCustomLength() {
        let pin4 = PINGenerator.generate(length: 4)
        XCTAssertEqual(pin4.count, 4)
        XCTAssertTrue(pin4.allSatisfy { $0.isNumber })

        let pin8 = PINGenerator.generate(length: 8)
        XCTAssertEqual(pin8.count, 8)
        XCTAssertTrue(pin8.allSatisfy { $0.isNumber })
    }

    func testGenerateZeroLength() {
        let pin = PINGenerator.generate(length: 0)
        XCTAssertEqual(pin.count, 0)
        XCTAssertEqual(pin, "")
    }

    func testGenerateProducesRandomValues() {
        // Generate multiple PINs and ensure they're not all identical
        let pins = (0..<10).map { _ in PINGenerator.generate() }
        let uniquePins = Set(pins)
        // With 10 random 6-digit PINs, we should have at least 2 different values
        // (probability of all 10 being identical is astronomically low)
        XCTAssertGreaterThan(uniquePins.count, 1)
    }

    // MARK: - Validation Tests

    func testIsValidWithValidPIN() {
        XCTAssertTrue(PINGenerator.isValid("123456"))
        XCTAssertTrue(PINGenerator.isValid("000000"))
        XCTAssertTrue(PINGenerator.isValid("999999"))
    }

    func testIsValidWithInvalidLength() {
        XCTAssertFalse(PINGenerator.isValid("12345"))    // Too short
        XCTAssertFalse(PINGenerator.isValid("1234567"))  // Too long
        XCTAssertFalse(PINGenerator.isValid(""))         // Empty
    }

    func testIsValidWithNonDigits() {
        XCTAssertFalse(PINGenerator.isValid("12345a"))
        XCTAssertFalse(PINGenerator.isValid("abcdef"))
        XCTAssertFalse(PINGenerator.isValid("12 456"))   // Space
        XCTAssertFalse(PINGenerator.isValid("123-56"))   // Dash
    }

    func testIsValidWithCustomLength() {
        XCTAssertTrue(PINGenerator.isValid("1234", length: 4))
        XCTAssertFalse(PINGenerator.isValid("123456", length: 4))
        XCTAssertTrue(PINGenerator.isValid("12345678", length: 8))
    }

    func testGeneratedPINsAreValid() {
        for _ in 0..<100 {
            let pin = PINGenerator.generate()
            XCTAssertTrue(PINGenerator.isValid(pin), "Generated PIN '\(pin)' should be valid")
        }
    }

    // MARK: - Constant-Time Comparison Tests

    func testCompareMatchingPINs() {
        XCTAssertTrue(PINGenerator.compare("123456", "123456"))
        XCTAssertTrue(PINGenerator.compare("000000", "000000"))
        XCTAssertTrue(PINGenerator.compare("", ""))
    }

    func testCompareNonMatchingPINs() {
        XCTAssertFalse(PINGenerator.compare("123456", "654321"))
        XCTAssertFalse(PINGenerator.compare("123456", "123457"))  // Last digit different
        XCTAssertFalse(PINGenerator.compare("123456", "023456"))  // First digit different
    }

    func testCompareDifferentLengths() {
        XCTAssertFalse(PINGenerator.compare("123456", "12345"))
        XCTAssertFalse(PINGenerator.compare("123456", "1234567"))
        XCTAssertFalse(PINGenerator.compare("", "1"))
    }

    func testCompareIsSymmetric() {
        let pin1 = "123456"
        let pin2 = "654321"
        XCTAssertEqual(
            PINGenerator.compare(pin1, pin2),
            PINGenerator.compare(pin2, pin1)
        )
    }
}
