import XCTest
@testable import AppReveal

final class AnyCodableTests: XCTestCase {
    func testDoubleValueReadsIntegerPayloads() {
        let value = AnyCodable(220)
        XCTAssertEqual(value.doubleValue, 220)
    }

    func testIntValueReadsDoublePayloads() {
        let value = AnyCodable(220.8)
        XCTAssertEqual(value.intValue, 220)
    }
}
