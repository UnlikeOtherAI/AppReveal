import XCTest
@testable import AppReveal

#if os(iOS) && DEBUG
import UIKit
import SwiftUI

@MainActor
final class IOSInteractionTests: XCTestCase {
    private var window: UIWindow!
    private let windowID = "appreveal-ios-tests"

    override func setUp() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.accessibilityIdentifier = windowID
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func testInvalidWindowDoesNotFallBackToAnotherWindow() async throws {
        let field = UITextField(frame: CGRect(x: 10, y: 100, width: 200, height: 50))
        field.accessibilityIdentifier = "input"
        window.rootViewController!.view.addSubview(field)
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertTrue(IOSWindowProvider.shared.windowsForInteraction(windowId: "missing").isEmpty)
        XCTAssertThrowsError(try InteractionEngine.shared.type(text: "wrong", elementId: nil, windowId: "missing"))
        XCTAssertEqual(field.text, "")
    }

    func testTypingAndClearingTextViewUpdateDelegateAndRejectReadOnly() async throws {
        let field = UITextView(frame: CGRect(x: 10, y: 100, width: 200, height: 80))
        field.accessibilityIdentifier = "input"
        let delegate = TextViewFixture()
        field.delegate = delegate
        window.rootViewController!.view.addSubview(field)
        try InteractionEngine.shared.type(text: "A😀B", elementId: "input", windowId: windowID)
        XCTAssertEqual(field.text, "A😀B")
        XCTAssertEqual(delegate.latest, "A😀B")
        try InteractionEngine.shared.clear(elementId: "input", windowId: windowID)
        XCTAssertEqual(field.text, "")
        XCTAssertEqual(delegate.latest, "")
        field.isEditable = false
        XCTAssertThrowsError(try InteractionEngine.shared.type(text: "bad", elementId: "input", windowId: windowID))
    }

    func testSwitchTapChangesStateAndDisabledButtonDoesNotFire() async throws {
        let toggle = UISwitch(frame: CGRect(x: 10, y: 100, width: 60, height: 32))
        toggle.accessibilityIdentifier = "toggle"
        window.rootViewController!.view.addSubview(toggle)
        try InteractionEngine.shared.tap(elementId: "toggle", windowId: windowID)
        XCTAssertTrue(toggle.isOn)
        toggle.isEnabled = false
        XCTAssertThrowsError(try InteractionEngine.shared.tap(elementId: "toggle", windowId: windowID))
        XCTAssertTrue(toggle.isOn)
    }

    func testLabelTapActivatesItsEnabledButtonAncestor() async throws {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 10, y: 100, width: 180, height: 44)
        button.setTitle("Action", for: .normal)
        button.titleLabel?.accessibilityIdentifier = "button.label"
        var taps = 0
        button.addAction(UIAction { _ in taps += 1 }, for: .touchUpInside)
        window.rootViewController!.view.addSubview(button)
        button.layoutIfNeeded()
        try InteractionEngine.shared.tap(elementId: "button.label", windowId: windowID)
        XCTAssertEqual(taps, 1)
        button.isEnabled = false
        XCTAssertThrowsError(try InteractionEngine.shared.tap(elementId: "button.label", windowId: windowID))
        XCTAssertEqual(taps, 1)
    }

    func testScrollClampsShortContentAndHonorsAdjustedInsets() async throws {
        let scroll = UIScrollView(frame: CGRect(x: 10, y: 100, width: 200, height: 300))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 20, height: 20)
        scroll.contentInset = UIEdgeInsets(top: 30, left: 10, bottom: 40, right: 20)
        scroll.accessibilityIdentifier = "scroll"
        window.rootViewController!.view.addSubview(scroll)
        scroll.contentOffset = CGPoint(x: -10, y: -30)
        try InteractionEngine.shared.scroll(direction: .down, containerId: "scroll", windowId: windowID)
        try InteractionEngine.shared.scroll(direction: .right, containerId: "scroll", windowId: windowID)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(scroll.contentOffset.x, -10, accuracy: 0.1)
        XCTAssertEqual(scroll.contentOffset.y, -30, accuracy: 0.1)
    }

    func testBackAtRootFailsAndPushCanBePopped() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        XCTAssertThrowsError(try InteractionEngine.shared.navigateBack(windowId: windowID))
        navigation.pushViewController(UIViewController(), animated: false)
        try InteractionEngine.shared.navigateBack(windowId: windowID)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testScreenTitleFollowsSelectedTabNavigation() async throws {
        let first = UIViewController()
        first.title = "First"
        let second = UIViewController()
        second.title = "Second"
        let tabs = UITabBarController()
        tabs.viewControllers = [UINavigationController(rootViewController: first), UINavigationController(rootViewController: second)]
        window.rootViewController = tabs
        tabs.selectedIndex = 1
        let screen = ScreenResolver.shared.resolve(windowId: windowID)
        XCTAssertEqual(screen.screenTitle, "Second")
        XCTAssertEqual(screen.appBarTitle, "Second")
    }

    func testScreenIgnoresSystemTextTrackingOverlay() async throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        let overlay = UIWindow(windowScene: try XCTUnwrap(window.windowScene))
        overlay.rootViewController = TestUITrackingElementWindowController()
        overlay.windowLevel = .alert + 1
        overlay.isHidden = false
        defer { overlay.isHidden = true }
        let screen = ScreenResolver.shared.resolve()
        XCTAssertEqual(screen.navigationDepth, 1)
        XCTAssertFalse(screen.controllerChain.contains { $0.contains("UITrackingElementWindowController") })
    }

    func testRegisteredSwiftUITextFieldAndLazyGridActivation() async throws {
        let model = SwiftUIFixtureModel()
        window.rootViewController = UIHostingController(rootView: SwiftUIFixture(model: model))
        try await Task.sleep(nanoseconds: 400_000_000)
        try InteractionEngine.shared.type(text: "Hello", elementId: "fixture.input", windowId: windowID)
        XCTAssertEqual(model.text, "Hello")
        try InteractionEngine.shared.clear(elementId: "fixture.input", windowId: windowID)
        XCTAssertEqual(model.text, "")
        let entry = try XCTUnwrap(SwiftUIElementRegistry.shared.findElement(byId: "fixture.button", windowIds: [windowID]))
        XCTAssertTrue(InteractionEngine.shared.tap(point: entry.frame.center, windowId: windowID))
        XCTAssertEqual(model.taps, 1)
        XCTAssertThrowsError(try InteractionEngine.shared.tap(elementId: "fixture.button", windowId: "missing"))
        XCTAssertThrowsError(try InteractionEngine.shared.tap(elementId: "fixture.disabled", windowId: windowID))
        XCTAssertEqual(model.taps, 1)
    }
}

private class TestUITrackingElementWindowController: UIViewController {}

@MainActor
private class TextViewFixture: NSObject, UITextViewDelegate {
    var latest = ""
    func textViewDidChange(_ textView: UITextView) { latest = textView.text }
}

@MainActor
private class SwiftUIFixtureModel: ObservableObject {
    @Published var text = ""
    @Published var taps = 0
}

private struct SwiftUIFixture: View {
    @ObservedObject var model: SwiftUIFixtureModel
    var body: some View {
        VStack {
            TextField("Input", text: $model.text)
                .appReveal("fixture.input", type: .textField)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible())]) {
                    Button("Disabled") { model.taps += 1 }
                        .appReveal("fixture.disabled", activate: { model.taps += 1 })
                        .disabled(true)
                    Button("Activate") { model.taps += 1 }
                        .appReveal("fixture.button", activate: { model.taps += 1 })
                }
            }
        }.padding()
    }
}
#endif
