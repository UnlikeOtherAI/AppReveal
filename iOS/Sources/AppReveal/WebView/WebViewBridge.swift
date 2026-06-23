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

#endif // os(iOS)

#endif // DEBUG
