import XCTest
@testable import AppReveal

#if os(macOS) && DEBUG
import AppKit
import SwiftUI

@MainActor
final class MacOSInteractionTests: XCTestCase {
    private var window: NSWindow!
    private let windowID = "appreveal-interaction-tests"

    override func setUp() async throws {
        _ = NSApplication.shared
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(windowID)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }

    override func tearDown() async throws {
        window.close()
        window = nil
    }

    func testInspectionEncodesUnconstrainedAppKitSafeAreas() async throws {
        let label = NSTextField(labelWithString: "Static label")
        label.frame = NSRect(x: 10, y: 10, width: 180, height: 24)
        label.setAccessibilityIdentifier("label")
        window.contentView!.addSubview(label)
        registerBuiltInTools()
        for name in ["get_elements", "get_view_tree"] {
            let tool = try XCTUnwrap(MCPRouter.shared.tool(named: name))
            let result = try await tool.handler(["window_id": AnyCodable(windowID)])
            XCTAssertNoThrow(try JSONEncoder().encode(result), name)
        }
        let element = try XCTUnwrap(ElementInventory.shared.listElements(windowId: windowID).first { $0.id == "label" })
        XCTAssertFalse(element.tappable)
        XCTAssertFalse(element.actions.contains("tap"))
        XCTAssertTrue(element.safeAreaLayoutGuideFrame.width.isFinite)
    }

    func testPointTapUsesWindowCoordinatesAndRejectsMisses() async throws {
        let root = FlippedView(frame: window.contentView!.bounds)
        window.contentView = root
        let receiver = ActionReceiver()
        let button = NSButton(title: "Run", target: receiver, action: #selector(ActionReceiver.run))
        button.frame = NSRect(x: 80, y: 40, width: 100, height: 30)
        button.setAccessibilityIdentifier("run")
        root.addSubview(button)
        let frame = button.convert(button.bounds, to: nil)
        XCTAssertTrue(MacOSInteractionEngine.shared.tap(point: CGPoint(x: frame.midX, y: frame.midY), windowId: windowID))
        XCTAssertEqual(receiver.count, 1)
        XCTAssertFalse(MacOSInteractionEngine.shared.tap(point: CGPoint(x: -100, y: -100), windowId: windowID))
        XCTAssertFalse(MacOSInteractionEngine.shared.tap(point: frame.origin, windowId: "missing-window"))
        button.isEnabled = false
        XCTAssertThrowsError(try MacOSInteractionEngine.shared.tap(elementId: "run", windowId: windowID))
        XCTAssertEqual(receiver.count, 1)
    }

    func testTableLabelTapSelectsRequestedRowAndNotifiesOnce() async throws {
        let table = NSTableView(frame: window.contentView!.bounds)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")))
        table.headerView = nil
        table.rowHeight = 40
        let delegate = TableFixture()
        table.dataSource = delegate
        table.delegate = delegate
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.documentView = table
        window.contentView!.addSubview(scroll)
        table.reloadData()
        window.contentView!.layoutSubtreeIfNeeded()
        _ = table.view(atColumn: 0, row: 1, makeIfNecessary: true)
        delegate.selections = 0
        try MacOSInteractionEngine.shared.tap(elementId: "row.1", windowId: windowID)
        XCTAssertEqual(table.selectedRow, 1)
        XCTAssertEqual(delegate.selections, 1)
        let match = ElementInventory.shared.findElementByText("Settings", occurrence: -1, windowId: windowID)
        XCTAssertTrue(match.isSuccess, match.error ?? "")
    }

    func testTextEditingUpdatesDelegateAndPreservesUTF16Selection() async throws {
        let field = NSTextField(string: "A😀B")
        field.frame = NSRect(x: 30, y: 100, width: 250, height: 26)
        field.setAccessibilityIdentifier("input")
        let delegate = TextFixture()
        field.delegate = delegate
        window.contentView!.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        try MacOSInteractionEngine.shared.type(text: "Z", elementId: "input", windowId: windowID)
        XCTAssertEqual(field.stringValue, "AZB")
        XCTAssertEqual(delegate.latest, "AZB")
        try MacOSInteractionEngine.shared.clear(elementId: "input", windowId: windowID)
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(delegate.latest, "")
        field.isEditable = false
        XCTAssertThrowsError(try MacOSInteractionEngine.shared.type(text: "no", elementId: "input", windowId: windowID))
        XCTAssertThrowsError(try MacOSInteractionEngine.shared.clear(elementId: "input", windowId: windowID))
    }

    func testMenuSubmenuAndMissingActionDoNotReportSuccess() async throws {
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let main = NSMenu()
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        file.submenu = NSMenu(title: "File")
        file.submenu!.addItem(NSMenuItem(title: "Unavailable", action: nil, keyEquivalent: ""))
        main.addItem(file)
        NSApp.mainMenu = main
        registerBuiltInTools()
        let tool = try XCTUnwrap(MCPRouter.shared.tool(named: "click_menu_item"))
        for path in ["File", "File > Unavailable"] {
            let result = try await tool.handler(["path": AnyCodable(path)])
            XCTAssertTrue(result.isToolFailure, path)
        }
    }

    func testEmbeddedSwiftUIUsesActualWindowCoordinatesAndTextBinding() async throws {
        let model = MacSwiftUIFixtureModel()
        let host = NSHostingView(rootView: MacSwiftUIFixture(model: model))
        host.frame = NSRect(x: 120, y: 100, width: 250, height: 200)
        window.contentView!.addSubview(host)
        try await Task.sleep(nanoseconds: 500_000_000)
        let entry = try XCTUnwrap(SwiftUIElementRegistry.shared.findElement(byId: "mac.fixture.button", windowIds: [windowID]))
        XCTAssertEqual(entry.windowId, windowID)
        XCTAssertGreaterThan(entry.frame.midY, 200)
        XCTAssertGreaterThan(entry.frame.minX, 120)
        XCTAssertTrue(MacOSInteractionEngine.shared.tap(point: entry.frame.center, windowId: windowID))
        XCTAssertEqual(model.taps, 1)
        try MacOSInteractionEngine.shared.type(text: "Hello", elementId: "mac.fixture.input", windowId: windowID)
        XCTAssertEqual(model.text, "Hello")
        try MacOSInteractionEngine.shared.clear(elementId: "mac.fixture.input", windowId: windowID)
        XCTAssertEqual(model.text, "")
        XCTAssertThrowsError(try MacOSInteractionEngine.shared.tap(elementId: "mac.fixture.button", windowId: "missing"))
        XCTAssertEqual(model.taps, 1)
    }

    func testSwitchChangesValueAndBackDoesNotReplaceSplitViewRoot() async throws {
        let toggle = NSSwitch(frame: NSRect(x: 10, y: 40, width: 60, height: 30))
        toggle.setAccessibilityIdentifier("toggle")
        window.contentView!.addSubview(toggle)
        try MacOSInteractionEngine.shared.tap(elementId: "toggle", windowId: windowID)
        XCTAssertEqual(toggle.state, .on)
        let split = NSSplitViewController()
        split.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        split.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        window.contentViewController = split
        XCTAssertThrowsError(try MacOSInteractionEngine.shared.navigateBack(windowId: windowID))
        XCTAssertTrue(window.contentViewController === split)
    }
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private class ActionReceiver: NSObject {
    var count = 0
    @objc func run() { count += 1 }
}

@MainActor
private class TextFixture: NSObject, NSTextFieldDelegate {
    var latest = ""
    func controlTextDidChange(_ notification: Notification) {
        latest = (notification.object as? NSTextField)?.stringValue ?? "missing"
    }
}

@MainActor
private class TableFixture: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var selections = 0
    func numberOfRows(in tableView: NSTableView) -> Int { 2 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        cell.setAccessibilityIdentifier("row.\(row)")
        let text = NSTextField(labelWithString: row == 0 ? "Orders" : "Settings")
        text.frame = NSRect(x: 8, y: 8, width: 160, height: 22)
        cell.textField = text
        cell.addSubview(text)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { selections += 1 }
}
@MainActor
private class MacSwiftUIFixtureModel: ObservableObject {
    @Published var text = ""
    @Published var taps = 0
}

private struct MacSwiftUIFixture: View {
    @ObservedObject var model: MacSwiftUIFixtureModel
    var body: some View {
        VStack {
            Button("Activate") { model.taps += 1 }
                .appReveal("mac.fixture.button", activate: { model.taps += 1 })
            TextField("Input", text: $model.text)
                .appReveal("mac.fixture.input", type: .textField)
            Spacer()
        }.padding()
    }
}
#endif
