import XCTest
@testable import AppReveal

#if os(macOS) && DEBUG
import AppKit
import WebKit

@MainActor
final class WebViewBehaviorTests: XCTestCase {
    private var window: NSWindow!
    private var webView: WKWebView!
    private let windowID = "appreveal-web-tests"

    override func setUp() async throws {
        _ = NSApplication.shared
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(windowID)
        window.isReleasedWhenClosed = false
        webView = WKWebView(frame: window.contentView!.bounds)
        webView.setAccessibilityIdentifier("web")
        window.contentView = webView
        window.orderFront(nil)
        let loaded = expectation(description: "HTML loaded")
        let navigation = WebNavigationFixture { loaded.fulfill() }
        webView.navigationDelegate = navigation
        webView.loadHTMLString("""
        <input id="text" value="initial"><input id="readonly" readonly value="original">
        <fieldset disabled><input id="disabled" value="original"><button id="button">Disabled</button></fieldset>
        <div id="editable" contenteditable>initial</div><p id="label">Static</p>
        <select id="select"><option value="a">A</option><option value="b">B</option><option disabled value="c">C</option></select>
        <input id="check" type="checkbox"><input id="radio" type="radio" checked>
        <script>window.inputEvents=0; document.addEventListener('input',()=>window.inputEvents++);</script>
        """, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        _ = navigation
    }

    override func tearDown() async throws {
        webView.stopLoading()
        window.close()
        webView = nil
        window = nil
    }

    func testJavaScriptScalarAndUndefinedResultsAreJSONSafe() async throws {
        let value1 = try await evaluate("42")
        XCTAssertEqual(value1, "42")
        let value2 = try await evaluate("true")
        XCTAssertEqual(value2, "true")
        let value3 = try await evaluate("null")
        XCTAssertEqual(value3, "null")
        let value4 = try await evaluate("void 0")
        XCTAssertEqual(value4, "null")
    }

    func testMissingDOMRootFailsThroughTheToolAndRecovers() async throws {
        registerMacOSWebViewTools()
        let tool = try XCTUnwrap(MCPRouter.shared.tool(named: "get_dom_tree"))
        let missing = try await tool.handler(["root": AnyCodable("#missing"), "window_id": AnyCodable(windowID)])
        XCTAssertTrue(missing.isToolFailure)
        let recovered = try await tool.handler(["root": AnyCodable("body"), "window_id": AnyCodable(windowID)])
        XCTAssertFalse(recovered.isToolFailure)
        let dom = try XCTUnwrap(recovered.dictionaryValue?["dom"]?.stringValue)
        let tree = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(dom.utf8)) as? [String: Any])
        XCTAssertEqual(tree["tag"] as? String, "body")
    }

    func testTypingNotifiesAndRejectsReadOnlyOrNonTextTargets() async throws {
        let typed = try await run(DOMSerializer.typeJS(selector: "#text", text: " updated", clear: false))
        XCTAssertEqual(typed["value"] as? String, "initial updated")
        let value5 = try await evaluate("window.inputEvents")
        XCTAssertEqual(value5, "1")
        let cleared = try await run(DOMSerializer.typeJS(selector: "#text", text: "", clear: true))
        XCTAssertEqual(cleared["value"] as? String, "")
        let editable = try await run(DOMSerializer.typeJS(selector: "#editable", text: "new", clear: true))
        XCTAssertEqual(editable["value"] as? String, "new")
        for selector in ["#readonly", "#disabled", "#label", "#check", "#missing"] {
            let result = try await run(DOMSerializer.typeJS(selector: selector, text: "bad", clear: true))
            XCTAssertNotNil(result["error"], selector)
        }
        let value6 = try await evaluate("document.querySelector('#readonly').value")
        XCTAssertEqual(value6, "original")
    }

    func testCheckboxClickEmitsOneInputEvent() async throws {
        let result = try await run(DOMSerializer.clickJS(selector: "#check"))
        XCTAssertEqual(result["checked"] as? Bool, true)
        let events = try await evaluate("window.inputEvents")
        XCTAssertEqual(events, "1")
    }

    func testSelectionAndToggleVerifyRequestedState() async throws {
        let selected = try await run(DOMSerializer.selectJS(selector: "#select", value: "b"))
        XCTAssertEqual(selected["value"] as? String, "b")
        for value in ["missing", "c"] {
            let result = try await run(DOMSerializer.selectJS(selector: "#select", value: value))
            XCTAssertNotNil(result["error"])
        }
        let value7 = try await evaluate("document.querySelector('#select').value")
        XCTAssertEqual(value7, "b")
        let checked = try await run(DOMSerializer.toggleJS(selector: "#check", checked: true))
        XCTAssertEqual(checked["checked"] as? Bool, true)
        let unchecked = try await run(DOMSerializer.toggleJS(selector: "#check", checked: false))
        XCTAssertEqual(unchecked["checked"] as? Bool, false)
        let radio = try await run(DOMSerializer.toggleJS(selector: "#radio", checked: false))
        XCTAssertNotNil(radio["error"])
        let label = try await run(DOMSerializer.toggleJS(selector: "#label", checked: true))
        XCTAssertNotNil(label["error"])
        let disabled = try await run(DOMSerializer.clickJS(selector: "#button"))
        XCTAssertNotNil(disabled["error"])
        registerMacOSWebViewTools()
        let tool = try XCTUnwrap(MCPRouter.shared.tool(named: "web_click"))
        let result = try await tool.handler(["selector": AnyCodable("#button"), "window_id": AnyCodable(windowID)])
        XCTAssertTrue(result.isToolFailure)
        XCTAssertNotNil(result.dictionaryValue?["result"]?.stringValue)
    }

    private func evaluate(_ js: String) async throws -> String {
        try await MacOSWebViewBridge.shared.evaluate(js: js, webViewId: "web", windowId: windowID)
    }

    private func run(_ js: String) async throws -> [String: Any] {
        let value = try await evaluate(js)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
}

@MainActor
private class WebNavigationFixture: NSObject, WKNavigationDelegate {
    let finished: () -> Void
    init(finished: @escaping () -> Void) { self.finished = finished }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }
}
#endif
