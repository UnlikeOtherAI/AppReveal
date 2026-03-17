// Discovers WKWebView instances and evaluates JavaScript in them

import Foundation
import UIKit
import WebKit

@MainActor
final class WebViewBridge {

    static let shared = WebViewBridge()

    private init() {}

    // MARK: - Discovery

    func findWebViews() -> [(id: String, webView: WKWebView)] {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else {
            return []
        }

        var results: [(id: String, webView: WKWebView)] = []
        var counter = 0
        collectWebViews(in: window, results: &results, counter: &counter)
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
