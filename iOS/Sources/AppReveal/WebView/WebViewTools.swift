// Registers WKWebView MCP tools with the router

import Foundation

#if DEBUG

#if os(iOS)

@MainActor
func registerWebViewTools() {
    let router = MCPRouter.shared
    let bridge = WebViewBridge.shared

    // MARK: - get_webviews

    router.register(MCPToolDefinition(
        name: "get_webviews",
        description: "List all WKWebView instances on the current screen with URL, title, loading state, and frame",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            let info = bridge.webViewInfo(windowId: windowId)
            return AnyCodable(["webviews": info, "count": info.count] as [String: Any])
        }
    ))

    // MARK: - get_dom_tree

    router.register(MCPToolDefinition(
        name: "get_dom_tree",
        description: "Get the DOM tree of a web view. Returns full or partial DOM structure as JSON.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "root": ["type": "string", "description": "CSS selector for subtree root (default: body)"],
                "max_depth": ["type": "integer", "description": "Max tree depth (default: 30)"],
                "visible_only": ["type": "boolean", "description": "Only visible elements (default: false)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let js = DOMSerializer.dumpTreeJS(
                root: params?["root"]?.stringValue,
                maxDepth: params?["max_depth"]?.intValue ?? 30,
                visibleOnly: params?["visible_only"]?.boolValue ?? false
            )
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["dom": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_interactive

    router.register(MCPToolDefinition(
        name: "get_dom_interactive",
        description: "Get all interactive DOM elements (inputs, buttons, links, selects) with their attributes, values, and selectors",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let js = DOMSerializer.interactiveJS()
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - query_dom

    router.register(MCPToolDefinition(
        name: "query_dom",
        description: "Query the DOM with a CSS selector. Returns matching elements with tag, text, attributes, rect.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "limit": ["type": "integer", "description": "Max results (default: 50)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["selector"])
        ],
        handler: { params in
            guard let selector = params?["selector"]?.stringValue else {
                return AnyCodable(["error": "selector required"])
            }
            let js = DOMSerializer.queryJS(selector: selector, limit: params?["limit"]?.intValue ?? 50)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - find_dom_text

    router.register(MCPToolDefinition(
        name: "find_dom_text",
        description: "Find DOM elements containing specific text",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "text": ["type": "string", "description": "Text to search for"],
                "tag": ["type": "string", "description": "Optional tag filter (e.g. 'button', 'a')"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["text"])
        ],
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "text required"])
            }
            let js = DOMSerializer.findTextJS(text: text, tag: params?["tag"]?.stringValue)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_click

    router.register(MCPToolDefinition(
        name: "web_click",
        description: "Click a DOM element by CSS selector",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["selector"])
        ],
        handler: { params in
            guard let selector = params?["selector"]?.stringValue else {
                return AnyCodable(["error": "selector required"])
            }
            let js = DOMSerializer.clickJS(selector: selector)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_type

    router.register(MCPToolDefinition(
        name: "web_type",
        description: "Type text into a DOM input or textarea by CSS selector",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector"],
                "text": ["type": "string", "description": "Text to type"],
                "clear": ["type": "boolean", "description": "Clear field first (default: false)"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["selector", "text"])
        ],
        handler: { params in
            guard let selector = params?["selector"]?.stringValue,
                  let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "selector and text required"])
            }
            let js = DOMSerializer.typeJS(selector: selector, text: text, clear: params?["clear"]?.boolValue ?? false)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_select

    router.register(MCPToolDefinition(
        name: "web_select",
        description: "Select an option in a dropdown by CSS selector",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector for the select element"],
                "value": ["type": "string", "description": "Option value to select"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["selector", "value"])
        ],
        handler: { params in
            guard let selector = params?["selector"]?.stringValue,
                  let value = params?["value"]?.stringValue else {
                return AnyCodable(["error": "selector and value required"])
            }
            let js = DOMSerializer.selectJS(selector: selector, value: value)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_toggle

    router.register(MCPToolDefinition(
        name: "web_toggle",
        description: "Check or uncheck a checkbox/radio by CSS selector",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector"],
                "checked": ["type": "boolean", "description": "Desired checked state"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["selector", "checked"])
        ],
        handler: { params in
            guard let selector = params?["selector"]?.stringValue,
                  let checked = params?["checked"]?.boolValue else {
                return AnyCodable(["error": "selector and checked required"])
            }
            let js = DOMSerializer.toggleJS(selector: selector, checked: checked)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_scroll_to

    router.register(MCPToolDefinition(
        name: "web_scroll_to",
        description: "Scroll a web view until a DOM element is visible",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["selector"])
        ],
        handler: { params in
            guard let selector = params?["selector"]?.stringValue else {
                return AnyCodable(["error": "selector required"])
            }
            let js = DOMSerializer.scrollToJS(selector: selector)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_evaluate

    router.register(MCPToolDefinition(
        name: "web_evaluate",
        description: "Run arbitrary JavaScript in a web view and return the result",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "javascript": ["type": "string", "description": "JavaScript to evaluate"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["javascript"])
        ],
        handler: { params in
            guard let js = params?["javascript"]?.stringValue else {
                return AnyCodable(["error": "javascript required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - web_navigate

    router.register(MCPToolDefinition(
        name: "web_navigate",
        description: "Navigate a web view to a URL",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "url": ["type": "string", "description": "URL to navigate to"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["url"])
        ],
        handler: { params in
            guard let urlStr = params?["url"]?.stringValue,
                  let url = URL(string: urlStr) else {
                return AnyCodable(["error": "Invalid URL"])
            }
            let windowId = params?["window_id"]?.stringValue
            guard let webView = bridge.resolveWebView(id: params?["webview_id"]?.stringValue, windowId: windowId) else {
                return AnyCodable(["error": "WebView not found"])
            }
            webView.load(URLRequest(url: url))
            return AnyCodable(["success": true, "url": urlStr] as [String: Any])
        }
    ))

    // MARK: - web_back

    router.register(MCPToolDefinition(
        name: "web_back",
        description: "Go back in web view history",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            guard let webView = bridge.resolveWebView(id: params?["webview_id"]?.stringValue, windowId: windowId) else {
                return AnyCodable(["error": "WebView not found"])
            }
            guard webView.canGoBack else {
                return AnyCodable(["error": "Cannot go back"])
            }
            webView.goBack()
            return AnyCodable(["success": true] as [String: Any])
        }
    ))

    // MARK: - web_forward

    router.register(MCPToolDefinition(
        name: "web_forward",
        description: "Go forward in web view history",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            guard let webView = bridge.resolveWebView(id: params?["webview_id"]?.stringValue, windowId: windowId) else {
                return AnyCodable(["error": "WebView not found"])
            }
            guard webView.canGoForward else {
                return AnyCodable(["error": "Cannot go forward"])
            }
            webView.goForward()
            return AnyCodable(["success": true] as [String: Any])
        }
    ))

    // MARK: - get_dom_links

    router.register(MCPToolDefinition(
        name: "get_dom_links",
        description: "Get all links on the page -- just text and href. Minimal tokens.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: DOMSerializer.linksJS(), webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_text

    router.register(MCPToolDefinition(
        name: "get_dom_text",
        description: "Get visible text content of the page stripped of all markup. Optionally scope to a CSS selector. Minimal tokens.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "selector": ["type": "string", "description": "CSS selector to scope text extraction (default: body)"],
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let js = DOMSerializer.textContentJS(selector: params?["selector"]?.stringValue)
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: js, webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_forms

    router.register(MCPToolDefinition(
        name: "get_dom_forms",
        description: "Get all forms and their fields with types, names, values, options, and selectors. Includes pages without <form> tags.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: DOMSerializer.formsJS(), webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_headings

    router.register(MCPToolDefinition(
        name: "get_dom_headings",
        description: "Get all headings (h1-h6) for page structure overview. Minimal tokens.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: DOMSerializer.headingsJS(), webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_images

    router.register(MCPToolDefinition(
        name: "get_dom_images",
        description: "Get all visible images with src, alt text, and dimensions.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: DOMSerializer.imagesJS(), webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_tables

    router.register(MCPToolDefinition(
        name: "get_dom_tables",
        description: "Get all tables with headers and row data.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: DOMSerializer.tablesJS(), webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_dom_summary

    router.register(MCPToolDefinition(
        name: "get_dom_summary",
        description: "Get a compact page summary: title, meta, headings (h1-h3), element counts (links, images, inputs, buttons), and form overview. Cheapest way to understand a page.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                let result = try await bridge.evaluate(js: DOMSerializer.summaryJS(), webViewId: params?["webview_id"]?.stringValue, windowId: windowId)
                return AnyCodable(["result": result] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))
}

#elseif os(macOS)

/// Placeholder -- macOS WebView tools will be implemented in Task 11.
@MainActor
func registerWebViewTools() {
    // Will be implemented when MacOSWebViewBridge is added
}

#endif // os

#endif // DEBUG
