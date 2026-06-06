import XCTest
@testable import AppReveal

#if DEBUG

@MainActor
final class NetworkObserverServiceTests: XCTestCase {
    override func tearDown() {
        NetworkObserverService.shared.clear()
        super.tearDown()
    }

    func testAddCallAppendsToRecentCalls() {
        NetworkObserverService.shared.addCall(
            CapturedRequest(method: "GET", url: "https://example.com")
        )

        XCTAssertEqual(NetworkObserverService.shared.recentCalls(limit: 10).count, 1)
        XCTAssertEqual(NetworkObserverService.shared.recentCalls(limit: 10).first?.url, "https://example.com")
    }
}

#endif
