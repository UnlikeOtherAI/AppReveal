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

    func testResponseHeadersAreRedactedIndividually() {
        let request = CapturedRequest(
            method: "GET",
            url: "https://example.com",
            responseHeaders: [
                "Set-Cookie": "secret",
                "X-Trace-Id": "trace-123"
            ]
        )

        XCTAssertEqual(request.responseHeaders?["Set-Cookie"], "[REDACTED]")
        XCTAssertEqual(request.responseHeaders?["X-Trace-Id"], "trace-123")
    }
}

#endif
