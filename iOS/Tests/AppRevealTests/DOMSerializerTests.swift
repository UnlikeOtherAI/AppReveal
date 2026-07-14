import CoreGraphics
import XCTest
@testable import AppReveal

#if DEBUG

final class DOMSerializerTests: XCTestCase {
    func testElementInventoryScriptProjectsDOMControlsForNativeInventory() {
        let script = DOMSerializer.elementInventoryJS()

        XCTAssertTrue(script.contains("data-testid"))
        XCTAssertTrue(script.contains("viewport"))
        XCTAssertTrue(script.contains("rawId"))
        XCTAssertTrue(script.contains("textField"))
        XCTAssertTrue(script.contains("toggle"))
    }

    func testPointClickScriptUsesDOMElementFromPointAndPointerEvents() {
        let script = DOMSerializer.pointClickJS(
            localPoint: CGPoint(x: 20, y: 30),
            webViewSize: CGSize(width: 200, height: 300)
        )

        XCTAssertTrue(script.contains("document.elementFromPoint"))
        XCTAssertTrue(script.contains("PointerEvent"))
        XCTAssertTrue(script.contains("target.click()"))
        XCTAssertTrue(script.contains("JSON.stringify"))
    }
}

#endif
