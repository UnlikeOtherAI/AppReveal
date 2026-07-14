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
}

#endif
