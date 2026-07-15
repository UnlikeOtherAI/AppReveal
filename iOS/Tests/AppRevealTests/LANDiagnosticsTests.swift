import XCTest
@testable import AppReveal

#if DEBUG && (os(iOS) || os(macOS))

final class LANDiagnosticsTests: XCTestCase {
    func testWarningsCallOutMissingLocalNetworkDeclarations() {
        let warnings = AppRevealLANDiagnostics.warnings(
            info: [:],
            interfaces: [],
            pathStatus: "unsatisfied"
        )

        XCTAssertTrue(warnings.contains { $0.contains("NSLocalNetworkUsageDescription") })
        XCTAssertTrue(warnings.contains { $0.contains("NSBonjourServices") })
        XCTAssertTrue(warnings.contains { $0.contains("No active non-loopback LAN address") })
        XCTAssertTrue(warnings.contains { $0.contains("unsatisfied path") })
    }

    func testWarningsAcceptAppRevealBonjourServiceWithTrailingDot() {
        let warnings = AppRevealLANDiagnostics.warnings(
            info: [
                "NSLocalNetworkUsageDescription": "Debug local network access",
                "NSBonjourServices": ["_appreveal._tcp."]
            ],
            interfaces: [
                AppRevealLANInterface(
                    name: "en0",
                    family: "ipv4",
                    address: "192.168.1.155",
                    isLoopback: false,
                    isPointToPoint: false,
                    isLinkLocal: false
                )
            ],
            pathStatus: "satisfied"
        )

        XCTAssertFalse(warnings.contains { $0.contains("NSLocalNetworkUsageDescription") })
        XCTAssertFalse(warnings.contains { $0.contains("NSBonjourServices") })
        XCTAssertFalse(warnings.contains { $0.contains("No active non-loopback LAN address") })
        XCTAssertFalse(warnings.contains { $0.contains("unsatisfied path") })
    }
}

#endif
