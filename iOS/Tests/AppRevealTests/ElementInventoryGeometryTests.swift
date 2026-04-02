import XCTest
@testable import AppReveal

#if os(iOS) && DEBUG

final class ElementInventoryGeometryTests: XCTestCase {
    @MainActor
    func testMakeFramePreservesRectGeometry() {
        let frame = ElementInventory.makeFrame(CGRect(x: 12.5, y: 34.25, width: 200.75, height: 88.5))

        XCTAssertEqual(frame.x, 12.5)
        XCTAssertEqual(frame.y, 34.25)
        XCTAssertEqual(frame.width, 200.75)
        XCTAssertEqual(frame.height, 88.5)
    }

    @MainActor
    func testMakeSafeAreaInsetsUsesLeadingTrailingForLeftToRightLayouts() {
        let insets = ElementInventory.makeSafeAreaInsets(
            UIEdgeInsets(top: 10, left: 20, bottom: 30, right: 40),
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(insets.top, 10)
        XCTAssertEqual(insets.leading, 20)
        XCTAssertEqual(insets.bottom, 30)
        XCTAssertEqual(insets.trailing, 40)
    }

    @MainActor
    func testMakeSafeAreaInsetsUsesLeadingTrailingForRightToLeftLayouts() {
        let insets = ElementInventory.makeSafeAreaInsets(
            UIEdgeInsets(top: 10, left: 20, bottom: 30, right: 40),
            layoutDirection: .rightToLeft
        )

        XCTAssertEqual(insets.top, 10)
        XCTAssertEqual(insets.leading, 40)
        XCTAssertEqual(insets.bottom, 30)
        XCTAssertEqual(insets.trailing, 20)
    }
}

#endif
