// Discovers WKWebView instances and evaluates JavaScript in them

import Foundation
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

    func findWebViews() -> [(id: String, webView: WKWebView)] {
        var results: [(id: String, webView: WKWebView)] = []
        var counter = 0
        for window in candidateWindows() {
            collectWebViews(in: window, results: &results, counter: &counter)
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

    func resolveWebView(id: String?) -> WKWebView? {
        let webViews = findWebViews()
        if let id = id {
            return webViews.first(where: { $0.id == id })?.webView
        }
        return webViews.first?.webView
    }

    @discardableResult
    func clickElement(at windowPoint: CGPoint) -> Bool {
        guard let webView = findWebViews()
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
        let js = """
        (() => {
          const viewWidth = Math.max(1, window.innerWidth || document.documentElement.clientWidth || \(webView.bounds.width));
          const viewHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || \(webView.bounds.height));
          const x = \(localPoint.x) * viewWidth / Math.max(1, \(webView.bounds.width));
          const y = \(localPoint.y) * viewHeight / Math.max(1, \(webView.bounds.height));
          const element = document.elementFromPoint(x, y);
          if (!element) {
            return JSON.stringify({ success: false, error: "no_dom_element", x, y });
          }
          const target = element.closest('button,a,input,textarea,select,label,[role="button"],[onclick]') || element;
          if (typeof target.focus === 'function') {
            try { target.focus({ preventScroll: true }); } catch (_) { target.focus(); }
          }
          const eventInit = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
          for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
            target.dispatchEvent(new MouseEvent(type, eventInit));
          }
          if (typeof target.click === 'function') {
            target.click();
          } else {
            target.dispatchEvent(new MouseEvent('click', eventInit));
          }
          return JSON.stringify({
            success: true,
            tag: target.tagName,
            id: target.id || null,
            text: (target.innerText || target.value || '').slice(0, 120)
          });
        })()
        """

        webView.evaluateJavaScript(js) { _, error in
            if let error {
                print("[AppReveal] WebView tap_point DOM click failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    @discardableResult
    func clickElement(selector: String, webViewId: String?) -> Bool {
        guard let webView = resolveWebView(id: webViewId) else {
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
    func clickElement(_ target: DOMElementTarget) -> Bool {
        clickElement(selector: target.selector, webViewId: target.webViewId)
    }

    @discardableResult
    func typeText(_ text: String, in target: DOMElementTarget, clear: Bool) -> Bool {
        guard target.actions.contains("type"),
              let webView = resolveWebView(id: target.webViewId) else {
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
    func clearText(in target: DOMElementTarget) -> Bool {
        typeText("", in: target, clear: true)
    }

    func domElementTargets() async -> [DOMElementTarget] {
        var targets: [DOMElementTarget] = []
        var seenIds: [String: Int] = [:]

        for item in findWebViews() {
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
                let inputType = (
                    Self.string(raw["inputType"]) ?? Self.string(raw["type"])
                )?.lowercased()
                let label = Self.firstNonEmpty([
                    Self.string(raw["label"]),
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
                let type = Self.elementType(tag: tag, inputType: inputType)
                let actions = Self.actions(for: type, enabled: !disabled)
                let rawId = Self.firstNonEmpty([
                    Self.string(raw["testId"]),
                    Self.string(raw["id"]),
                    Self.string(raw["name"]).map { "\(tag)_\($0)" },
                    Self.string(raw["ariaLabel"]),
                    Self.string(raw["placeholder"]),
                    Self.string(raw["text"]),
                    "\(tag)_\(index)"
                ]) ?? "\(tag)_\(index)"
                let id = Self.deduplicatedId(
                    "web.\(Self.normalizeIdComponent(item.id)).\(Self.normalizeIdComponent(rawId))",
                    seenIds: &seenIds
                )
                let textCandidates = [
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

    func findDOMElementTarget(id: String) async -> DOMElementTarget? {
        await domElementTargets().first { $0.id == id }
    }

    func matchingDOMElementTargets(text: String, matchMode: String = "exact") async -> [DOMElementTarget] {
        await domElementTargets().filter { $0.matches(text: text, matchMode: matchMode) }
    }

    // MARK: - Metadata

    func webViewInfo() -> [[String: Any]] {
        findWebViews().map { item in
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

    func evaluate(js: String, webViewId: String?) async throws -> String {
        guard let webView = resolveWebView(id: webViewId) else {
            throw WebViewError.notFound(webViewId ?? "default")
        }

        let result = try await webView.evaluateJavaScript(js)
        if let string = result as? String {
            return string
        }
        // For non-string results, convert to JSON
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private func interactivePayload(for webView: WKWebView) async throws -> [String: Any] {
        let result = try await webView.evaluateJavaScript(DOMSerializer.interactiveJS())
        let json: String
        if let string = result as? String {
            json = string
        } else {
            let data = try JSONSerialization.data(withJSONObject: result, options: [])
            json = String(data: data, encoding: .utf8) ?? "{}"
        }
        guard let data = json.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return payload
    }

    private static func elementType(tag: String, inputType: String?) -> ElementType {
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

    private func candidateWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0 && !$0.bounds.isEmpty }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.windowLevel != rhs.element.windowLevel {
                    return lhs.element.windowLevel > rhs.element.windowLevel
                }
                if lhs.element.isKeyWindow != rhs.element.isKeyWindow {
                    return lhs.element.isKeyWindow && !rhs.element.isKeyWindow
                }
                return lhs.offset > rhs.offset
            }
            .map(\.element)
    }
}

// MARK: - Errors

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
