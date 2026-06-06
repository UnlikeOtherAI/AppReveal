import XCTest
@testable import AppReveal

#if DEBUG

final class CapturedRequestTests: XCTestCase {
    func testSensitiveHeadersAreRedactedIndividually() {
        let request = CapturedRequest(
            method: "POST",
            url: "https://example.com",
            requestHeaders: [
                "Authorization": "secret",
                "X-Trace-Id": "trace-123"
            ]
        )

        XCTAssertEqual(request.requestHeaders["Authorization"], "[REDACTED]")
        XCTAssertEqual(request.requestHeaders["X-Trace-Id"], "trace-123")
    }
}

#endif
