// macOS WKWebView discovery and JavaScript evaluation

import Foundation

#if DEBUG
#if os(macOS)

import AppKit
import WebKit

@MainActor
final class MacOSWebViewBridge {

    static let shared = MacOSWebViewBridge()

    private init() {}

    // MARK: - Discovery

    func findWebViews(windowId: String? = nil) -> [(id: String, webView: WKWebView)] {
        guard
            let nativeWindow = MacOSWindowProvider.shared.resolve(windowId: windowId)?.nativeWindow,
            let contentView = nativeWindow.contentView
        else {
            return []
        }

        var results: [(id: String, webView: WKWebView)] = []
        var counter = 0
        collectWebViews(in: contentView, results: &results, counter: &counter)
        return results
    }

    private func collectWebViews(in view: NSView, results: inout [(id: String, webView: WKWebView)], counter: inout Int) {
        if let webView = view as? WKWebView {
            let accessibilityId = view.accessibilityIdentifier()
            let id = accessibilityId.isEmpty ? "webview_\(counter)" : accessibilityId
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

        let result = try await webView.evaluateJavaScript(js)
        if let string = result as? String {
            return string
        }
        // For non-string results, convert to JSON
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        return String(data: data, encoding: .utf8) ?? "null"
    }
}

#endif // os(macOS)
#endif // DEBUG
