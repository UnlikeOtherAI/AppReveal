// Discovers WKWebView instances and evaluates JavaScript in them

import Foundation

#if DEBUG

// MARK: - Errors (cross-platform)

enum WebViewError: LocalizedError {
    case notFound(String)
    case evaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "WebView not found: \(id)"
        case .evaluationFailed(let msg): return "JS evaluation failed: \(msg)"
        }
    }
}

#if os(iOS)

import UIKit
import WebKit

@MainActor
struct DOMElementTarget {
    let id: String
    let webViewId: String
    let selector: String
    let type: ElementType
    let label: String?
    let value: String?
    let enabled: Bool
    let frame: CGRect
    let actions: [String]
    let textCandidates: [String]

    var centerPoint: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    var elementInfo: ElementInfo {
        ElementInfo(
            id: id,
            type: type,
            label: label,
            value: value,
            enabled: enabled,
            visible: frame.width > 0 && frame.height > 0,
            tappable: actions.contains("tap"),
            frame: ElementInventory.makeFrame(frame),
            safeAreaInsets: ElementInfo.ElementInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            safeAreaLayoutGuideFrame: ElementInventory.makeFrame(frame),
            containerId: webViewId,
            actions: actions,
            idSource: "dom"
        )
    }

    func matches(text query: String, matchMode: String) -> Bool {
        textCandidates.contains { candidate in
            switch matchMode {
            case "contains":
                return candidate.localizedCaseInsensitiveContains(query)
            default:
                return candidate == query
            }
        }
    }
}

@MainActor
final class WebViewBridge {

    static let shared = WebViewBridge()

    private init() {}

    // MARK: - Discovery

    func findWebViews(windowId: String? = nil) -> [(id: String, webView: WKWebView)] {
        var results: [(id: String, webView: WKWebView)] = []
        var counter = 0
        for ref in IOSWindowProvider.shared.windowsForInteraction(windowId: windowId) {
            collectWebViews(in: ref.nativeWindow, results: &results, counter: &counter)
        }
        return results
    }

    private func collectWebViews(in view: UIView, results: inout [(id: String, webView: WKWebView)], counter: inout Int) {
        if let webView = view as? WKWebView {
            let id = view.accessibilityIdentifier ?? "webview_\(counter)"
            results.append((id: id, webView: webView))
            counter += 1
        }
        for subview in view.subviews where !subview.isHidden {
            collectWebViews(in: subview, results: &results, counter: &counter)
        }
    }

    func resolveWebView(id: String?, windowId: String? = nil) -> WKWebView? {
        let webViews = findWebViews(windowId: windowId)
        if let id = id {
            return webViews.first(where: { $0.id == id })?.webView
        }
        return webViews.first?.webView
    }

    @discardableResult
    func clickElement(at windowPoint: CGPoint, windowId: String? = nil) -> Bool {
        guard let webView = findWebViews(windowId: windowId)
            .map(\.webView)
            .first(where: { webView in
                webView.convert(webView.bounds, to: nil).contains(windowPoint)
            }) else {
            return false
        }
        return clickElement(at: windowPoint, in: webView)
    }

    @discardableResult
    func clickElement(at windowPoint: CGPoint, in webView: WKWebView) -> Bool {
        guard webView.convert(webView.bounds, to: nil).contains(windowPoint) else {
            return false
        }
        let localPoint = webView.convert(windowPoint, from: nil)
        let js = DOMSerializer.pointClickJS(localPoint: localPoint, webViewSize: webView.bounds.size)

        webView.evaluateJavaScript(js) { _, error in
            if let error {
                print("[AppReveal] WebView tap_point DOM click failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    func clickElementResult(at windowPoint: CGPoint, windowId: String? = nil) async -> [String: Any]? {
        guard let webView = findWebViews(windowId: windowId)
            .map(\.webView)
            .first(where: { webView in
                webView.convert(webView.bounds, to: nil).contains(windowPoint)
            }) else {
            return nil
        }

        let localPoint = webView.convert(windowPoint, from: nil)
        let js = DOMSerializer.pointClickJS(localPoint: localPoint, webViewSize: webView.bounds.size)
        do {
            let result = try await evaluate(js: js, in: webView)
            return Self.jsonDictionary(from: result)
        } catch {
            print("[AppReveal] WebView tap_point DOM click failed: \(error.localizedDescription)")
            return [
                "success": false,
                "error": error.localizedDescription
            ]
        }
    }

    @discardableResult
    func clickElement(selector: String, webViewId: String?, windowId: String? = nil) -> Bool {
        guard let webView = resolveWebView(id: webViewId, windowId: windowId) else {
            return false
        }
        webView.evaluateJavaScript(DOMSerializer.clickJS(selector: selector)) { _, error in
            if let error {
                print("[AppReveal] WebView DOM click failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    @discardableResult
    func clickElement(_ target: DOMElementTarget, windowId: String? = nil) -> Bool {
        clickElement(selector: target.selector, webViewId: target.webViewId, windowId: windowId)
    }

    func clickElementResult(_ target: DOMElementTarget, windowId: String? = nil) async -> [String: Any]? {
        guard let webView = resolveWebView(id: target.webViewId, windowId: windowId) else {
            return nil
        }
        do {
            let result = try await evaluate(js: DOMSerializer.clickJS(selector: target.selector), in: webView)
            return Self.jsonDictionary(from: result)
        } catch {
            print("[AppReveal] WebView DOM click failed: \(error.localizedDescription)")
            return [
                "success": false,
                "error": error.localizedDescription
            ]
        }
    }

    @discardableResult
    func typeText(_ text: String, in target: DOMElementTarget, clear: Bool, windowId: String? = nil) -> Bool {
        guard target.actions.contains("type"),
              let webView = resolveWebView(id: target.webViewId, windowId: windowId) else {
            return false
        }
        webView.evaluateJavaScript(DOMSerializer.typeJS(selector: target.selector, text: text, clear: clear)) { _, error in
            if let error {
                print("[AppReveal] WebView DOM type failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    @discardableResult
    func clearText(in target: DOMElementTarget, windowId: String? = nil) -> Bool {
        typeText("", in: target, clear: true, windowId: windowId)
    }

    func domElementTargets(windowId: String? = nil) async -> [DOMElementTarget] {
        var targets: [DOMElementTarget] = []
        var seenIds: [String: Int] = [:]

        for item in findWebViews(windowId: windowId) {
            guard let payload = try? await interactivePayload(for: item.webView),
                  let rawElements = payload["elements"] as? [[String: Any]] else {
                continue
            }

            let viewport = payload["viewport"] as? [String: Any]
            let viewportWidth = Self.cgFloat(viewport?["w"])
                ?? Self.cgFloat(viewport?["width"])
                ?? max(item.webView.bounds.width, 1)
            let viewportHeight = Self.cgFloat(viewport?["h"])
                ?? Self.cgFloat(viewport?["height"])
                ?? max(item.webView.bounds.height, 1)
            let scaleX = item.webView.bounds.width / max(viewportWidth, 1)
            let scaleY = item.webView.bounds.height / max(viewportHeight, 1)
            let webViewFrame = item.webView.convert(item.webView.bounds, to: nil)

            for (index, raw) in rawElements.enumerated() {
                guard let selector = Self.string(raw["selector"]),
                      let rect = raw["rect"] as? [String: Any],
                      let x = Self.cgFloat(rect["x"]),
                      let y = Self.cgFloat(rect["y"]),
                      let width = Self.cgFloat(rect["w"]),
                      let height = Self.cgFloat(rect["h"]) else {
                    continue
                }

                let frame = CGRect(
                    x: webViewFrame.origin.x + (x * scaleX),
                    y: webViewFrame.origin.y + (y * scaleY),
                    width: width * scaleX,
                    height: height * scaleY
                )
                guard frame.width > 0 || frame.height > 0 else { continue }

                let tag = Self.string(raw["tag"])?.lowercased() ?? "element"
                let inputType = Self.string(raw["inputType"])?.lowercased()
                let label = Self.firstNonEmpty([
                    Self.string(raw["label"]),
                    Self.string(raw["labelText"]),
                    Self.string(raw["ariaLabel"]),
                    Self.string(raw["text"]),
                    Self.string(raw["placeholder"]),
                    Self.string(raw["name"]),
                    Self.string(raw["id"]),
                    Self.string(raw["testId"])
                ])
                let value = Self.string(raw["value"])
                let enabledValue = raw["enabled"] as? Bool
                let disabled = (raw["disabled"] as? Bool) == true || enabledValue == false
                let type = Self.elementType(rawType: Self.string(raw["type"]), tag: tag, inputType: inputType)
                let actions = Self.actions(for: type, enabled: !disabled)
                let rawId = Self.firstNonEmpty([
                    Self.string(raw["rawId"]),
                    Self.string(raw["testId"]),
                    Self.string(raw["id"]),
                    Self.string(raw["name"]).map { "\(tag)_\($0)" },
                    Self.string(raw["ariaLabel"]),
                    Self.string(raw["labelText"]),
                    Self.string(raw["label"]),
                    Self.string(raw["placeholder"]),
                    Self.string(raw["text"]),
                    "\(tag)_\(index)"
                ]) ?? "\(tag)_\(index)"
                let id = Self.deduplicatedId(
                    "web.\(Self.normalizeIdComponent(item.id)).\(Self.normalizeIdComponent(rawId))",
                    seenIds: &seenIds
                )
                let textCandidates = [
                    label,
                    Self.string(raw["labelText"]),
                    Self.string(raw["label"]),
                    Self.string(raw["text"]),
                    Self.string(raw["ariaLabel"]),
                    Self.string(raw["placeholder"]),
                    Self.string(raw["value"]),
                    Self.string(raw["name"]),
                    Self.string(raw["id"]),
                    Self.string(raw["testId"])
                ].compactMap { $0 }.filter { !$0.isEmpty }

                targets.append(
                    DOMElementTarget(
                        id: id,
                        webViewId: item.id,
                        selector: selector,
                        type: type,
                        label: label,
                        value: value,
                        enabled: !disabled,
                        frame: frame,
                        actions: actions,
                        textCandidates: textCandidates
                    )
                )
            }
        }

        return targets
    }

    func findDOMElementTarget(id: String, windowId: String? = nil) async -> DOMElementTarget? {
        await domElementTargets(windowId: windowId).first { $0.id == id }
    }

    func matchingDOMElementTargets(
        text: String,
        matchMode: String = "exact",
        windowId: String? = nil
    ) async -> [DOMElementTarget] {
        await domElementTargets(windowId: windowId).filter { $0.matches(text: text, matchMode: matchMode) }
    }

    // MARK: - Metadata

    func webViewInfo(windowId: String? = nil) -> [[String: Any]] {
        findWebViews(windowId: windowId).map { item in
            let screenFrame = item.webView.convert(item.webView.bounds, to: nil)
            return [
                "id": item.id,
                "url": item.webView.url?.absoluteString ?? "",
                "title": item.webView.title ?? "",
                "loading": item.webView.isLoading,
                "canGoBack": item.webView.canGoBack,
                "canGoForward": item.webView.canGoForward,
                "frame": "\(Int(screenFrame.origin.x)),\(Int(screenFrame.origin.y)),\(Int(screenFrame.size.width)),\(Int(screenFrame.size.height))"
            ] as [String: Any]
        }
    }

    // MARK: - JavaScript evaluation

    func evaluate(js: String, webViewId: String?, windowId: String? = nil) async throws -> String {
        guard let webView = resolveWebView(id: webViewId, windowId: windowId) else {
            throw WebViewError.notFound(webViewId ?? "default")
        }

        return try await evaluate(js: js, in: webView)
    }

    private func evaluate(js: String, in webView: WKWebView) async throws -> String {
        let result = try await webView.evaluateJavaScript(js)
        if let string = result as? String {
            return string
        }
        guard let result else {
            return "null"
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private func interactivePayload(for webView: WKWebView) async throws -> [String: Any] {
        let json = try await evaluate(js: DOMSerializer.elementInventoryJS(), in: webView)
        return Self.jsonDictionary(from: json) ?? [:]
    }

    private static func elementType(rawType: String?, tag: String, inputType: String?) -> ElementType {
        if let rawType, let type = ElementType(rawValue: rawType) {
            return type
        }
        switch tag {
        case "button", "a":
            return .button
        case "textarea":
            return .textField
        case "select":
            return .picker
        case "input":
            switch inputType {
            case "checkbox", "radio":
                return .toggle
            case "button", "submit", "reset":
                return .button
            default:
                return .textField
            }
        default:
            return .other
        }
    }

    private static func actions(for type: ElementType, enabled: Bool) -> [String] {
        guard enabled else { return [] }
        switch type {
        case .textField:
            return ["tap", "type", "clear"]
        case .picker:
            return ["tap", "select"]
        case .toggle:
            return ["tap", "toggle"]
        default:
            return ["tap"]
        }
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let double = value as? Double { return CGFloat(double) }
        if let string = value as? String, let double = Double(string) { return CGFloat(double) }
        return nil
    }

    private static func jsonDictionary(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func normalizeIdComponent(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalized = normalized.replacingOccurrences(
            of: "\\s+", with: "_", options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: "[^a-z0-9_.-]", with: "", options: .regularExpression
        )
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return normalized.isEmpty ? "element" : String(normalized.prefix(80))
    }

    private static func deduplicatedId(_ id: String, seenIds: inout [String: Int]) -> String {
        let count = seenIds[id, default: 0]
        seenIds[id] = count + 1
        return count == 0 ? id : "\(id)_\(count)"
    }
}

#endif // os(iOS)

#endif // DEBUG
