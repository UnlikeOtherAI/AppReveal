import XCTest
@testable import AppReveal

#if DEBUG && (os(iOS) || os(macOS))

@MainActor
final class SwiftUIElementRegistryTests: XCTestCase {
    func testRegisteredTextFieldAdvertisesEditableActions() {
        let id = "test.swiftui.field.\(UUID().uuidString)"

        SwiftUIElementRegistry.shared.register(
            id: id,
            frame: CGRect(x: 10, y: 20, width: 120, height: 36),
            label: "Editable field",
            type: .textField
        )

        let element = SwiftUIElementRegistry.shared.findElement(byId: id, windowIds: [])

        XCTAssertEqual(element?.type, .textField)
        XCTAssertEqual(element?.label, "Editable field")
        XCTAssertEqual(element?.actions, ["tap", "type", "clear"])
        XCTAssertEqual(element?.isTappable, true)

        SwiftUIElementRegistry.shared.unregister(id: id)
    }

    func testTransientUnregisterIsCancelledByReregister() async throws {
        let id = "test.swiftui.transient.\(UUID().uuidString)"

        SwiftUIElementRegistry.shared.register(
            id: id,
            frame: CGRect(x: 10, y: 20, width: 120, height: 36),
            label: "First",
            type: .button
        )

        SwiftUIElementRegistry.shared.unregister(id: id)
        SwiftUIElementRegistry.shared.register(
            id: id,
            frame: CGRect(x: 12, y: 22, width: 130, height: 40),
            label: "Second",
            type: .textField
        )

        try await Task.sleep(nanoseconds: 350_000_000)

        let element = SwiftUIElementRegistry.shared.findElement(byId: id, windowIds: [])
        XCTAssertEqual(element?.label, "Second")
        XCTAssertEqual(element?.type, .textField)

        SwiftUIElementRegistry.shared.unregister(id: id)
    }

    func testFindTappableElementAtPointPrefersSmallestContainingFrame() {
        let outerId = "test.swiftui.outer.\(UUID().uuidString)"
        let innerId = "test.swiftui.inner.\(UUID().uuidString)"

        SwiftUIElementRegistry.shared.register(
            id: outerId,
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            label: "Outer",
            type: .button
        )
        SwiftUIElementRegistry.shared.register(
            id: innerId,
            frame: CGRect(x: 50, y: 50, width: 40, height: 40),
            label: "Inner",
            type: .button
        )

        let element = SwiftUIElementRegistry.shared.findTappableElement(
            at: CGPoint(x: 60, y: 60),
            windowIds: []
        )

        XCTAssertEqual(element?.id, innerId)

        SwiftUIElementRegistry.shared.unregister(id: outerId)
        SwiftUIElementRegistry.shared.unregister(id: innerId)
    }
}

#endif
