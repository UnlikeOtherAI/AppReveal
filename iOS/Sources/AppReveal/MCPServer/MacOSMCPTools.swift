import Foundation

#if DEBUG
#if os(macOS)

import AppKit
import WebKit

@MainActor
func registerMacOSBuiltInToolsImpl() {
    let router = MCPRouter.shared

    router.register(MCPToolDefinition(
        name: "get_screen",
        description: "Get the currently active screen identity and metadata",
        inputSchema: macOSInputSchema(),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            let info = MacOSScreenResolver.shared.resolve(windowId: windowId)
            return AnyCodable([
                "screenKey": info.screenKey,
                "screenTitle": info.screenTitle,
                "frameworkType": info.frameworkType,
                "controllerChain": info.controllerChain,
                "activeTab": info.activeTab as Any,
                "navigationDepth": info.navigationDepth,
                "presentedModals": info.presentedModals,
                "confidence": info.confidence,
                "source": info.source,
                "appBarTitle": info.appBarTitle as Any
            ] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_elements",
        description: "List all visible interactive elements on the current screen. Elements include an idSource field showing how the ID was derived.",
        inputSchema: macOSInputSchema(),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            let screenInfo = MacOSScreenResolver.shared.resolve(windowId: windowId)
            let elements = ElementInventory.shared.listElements(windowId: windowId)
            let list = elements.map { el in
                [
                    "id": el.id,
                    "type": el.type.rawValue,
                    "label": el.label ?? "",
                    "value": el.value ?? "",
                    "enabled": el.enabled ? "true" : "false",
                    "visible": el.visible ? "true" : "false",
                    "tappable": el.tappable ? "true" : "false",
                    "frame": "\(Int(el.frame.x)),\(Int(el.frame.y)),\(Int(el.frame.width)),\(Int(el.frame.height))",
                    "actions": el.actions.joined(separator: ","),
                    "idSource": el.idSource
                ] as [String: String]
            }
            return AnyCodable([
                "screenKey": screenInfo.screenKey,
                "elements": list
            ] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "screenshot",
        description: "Capture a screenshot of the current screen. Returns base64-encoded image.",
        inputSchema: macOSInputSchema([
            "element_id": ["type": "string", "description": "Optional element ID to crop to"],
            "format": ["type": "string", "enum": ["png", "jpeg"], "description": "Image format (default: png)"]
        ]),
        handler: { params in
            let format: ImageFormat = params?["format"]?.stringValue == "jpeg" ? .jpeg : .png
            let windowId = params?["window_id"]?.stringValue
            let result: MacOSScreenshotCapture.CaptureResult?

            if let elementId = params?["element_id"]?.stringValue {
                result = MacOSScreenshotCapture.shared.captureElement(id: elementId, format: format, windowId: windowId)
            } else {
                result = MacOSScreenshotCapture.shared.captureScreen(format: format, windowId: windowId)
            }

            guard let capture = result else {
                return AnyCodable(["error": "Failed to capture screenshot"])
            }

            return AnyCodable([
                "image": capture.imageData.base64EncodedString(),
                "width": capture.width,
                "height": capture.height,
                "scale": capture.scale,
                "format": capture.format
            ] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "tap_element",
        description: "Tap an element by ID. Resolves by accessibilityIdentifier, accessibilityLabel, derived text ID, or visible text (in that order). If not found, try tap_text.",
        inputSchema: macOSInputSchema([
            "element_id": ["type": "string", "description": "Element ID (accessibilityIdentifier, derived text ID, or visible text)"]
        ], required: ["element_id"]),
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.tap(elementId: elementId, windowId: windowId)
                return AnyCodable(["success": true, "element_id": elementId] as [String: Any])
            } catch {
                return AnyCodable(["error": "\(error.localizedDescription). Try tap_text for visible text targeting, or get_elements to list available IDs."])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "tap_text",
        description: "Tap the nearest tappable element containing the given visible text. Use when you know what text is on screen but not the element ID.",
        inputSchema: macOSInputSchema([
            "text": ["type": "string", "description": "Visible text to find and tap"],
            "match_mode": ["type": "string", "enum": ["exact", "contains"], "description": "Match mode (default: exact)"],
            "occurrence": ["type": "integer", "description": "0-based index when multiple matches exist"]
        ], required: ["text"]),
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "text required"])
            }
            let matchMode = params?["match_mode"]?.stringValue ?? "exact"
            let occurrence = params?["occurrence"]?.intValue ?? -1
            let windowId = params?["window_id"]?.stringValue

            let result = ElementInventory.shared.findElementByText(
                text, matchMode: matchMode, occurrence: occurrence, windowId: windowId
            )

            guard result.isSuccess, let view = result.view else {
                var response: [String: Any] = ["error": result.error ?? "Unknown error"]
                if let candidates = result.candidates {
                    response["candidates"] = candidates
                    response["hint"] = "Use occurrence parameter (0-based) to select a specific match"
                }
                return AnyCodable(response)
            }

            let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            MacOSInteractionEngine.shared.tap(point: view.convert(point, to: nil), windowId: windowId)
            return AnyCodable(["success": true, "text": text] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "tap_point",
        description: "Tap at specific screen coordinates",
        inputSchema: macOSInputSchema([
            "x": ["type": "number"],
            "y": ["type": "number"]
        ], required: ["x", "y"]),
        handler: { params in
            let x = params?["x"]?.doubleValue ?? 0
            let y = params?["y"]?.doubleValue ?? 0
            let windowId = params?["window_id"]?.stringValue
            MacOSInteractionEngine.shared.tap(point: CGPoint(x: x, y: y), windowId: windowId)
            return AnyCodable(["success": true, "x": x, "y": y] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "type_text",
        description: "Type text into a text field",
        inputSchema: macOSInputSchema([
            "text": ["type": "string", "description": "Text to type"],
            "element_id": ["type": "string", "description": "Optional target element ID"]
        ], required: ["text"]),
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "text required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.type(
                    text: text,
                    elementId: params?["element_id"]?.stringValue,
                    windowId: windowId
                )
                return AnyCodable(["success": true, "text": text] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "clear_text",
        description: "Clear a text field",
        inputSchema: macOSInputSchema([
            "element_id": ["type": "string"]
        ], required: ["element_id"]),
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.clear(elementId: elementId, windowId: windowId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "scroll",
        description: "Scroll a container in a direction",
        inputSchema: macOSInputSchema([
            "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
            "container_id": ["type": "string", "description": "Optional scroll view ID"]
        ], required: ["direction"]),
        handler: { params in
            guard let dirStr = params?["direction"]?.stringValue,
                  let direction = ScrollDirection(rawValue: dirStr) else {
                return AnyCodable(["error": "Invalid direction"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.scroll(
                    direction: direction,
                    containerId: params?["container_id"]?.stringValue,
                    windowId: windowId
                )
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "scroll_to_element",
        description: "Scroll until an element is visible",
        inputSchema: macOSInputSchema([
            "element_id": ["type": "string"]
        ], required: ["element_id"]),
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.scrollTo(elementId: elementId, windowId: windowId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "select_tab",
        description: "Switch to a tab by index (0-based)",
        inputSchema: macOSInputSchema([
            "index": ["type": "integer", "description": "Tab index (0-based)"]
        ], required: ["index"]),
        handler: { params in
            guard let index = params?["index"]?.intValue else {
                return AnyCodable(["error": "index required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.selectTab(index: index, windowId: windowId)
                return AnyCodable(["success": true, "tab_index": index] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "navigate_back",
        description: "Pop the current navigation stack",
        inputSchema: macOSInputSchema(),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.navigateBack(windowId: windowId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "dismiss_modal",
        description: "Dismiss the topmost presented modal",
        inputSchema: macOSInputSchema(),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                try MacOSInteractionEngine.shared.dismissModal(windowId: windowId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_view_tree",
        description: "Dump the full view hierarchy of the current screen. Returns every view with class, frame, properties, accessibility info, and depth. Use for discovering all objects on screen.",
        inputSchema: macOSInputSchema([
            "max_depth": ["type": "integer", "description": "Max hierarchy depth (default 50)"]
        ]),
        handler: { params in
            let maxDepth = params?["max_depth"]?.intValue ?? 50
            let windowId = params?["window_id"]?.stringValue
            let tree = ElementInventory.shared.dumpViewTree(maxDepth: maxDepth, windowId: windowId)
            return AnyCodable(["views": tree, "count": tree.count] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_menu_bar",
        description: "Read the NSApplication main menu hierarchy recursively with titles, shortcuts, and enabled state.",
        inputSchema: macOSInputSchema(),
        handler: { params in
            _ = params?["window_id"]?.stringValue
            guard let menu = NSApplication.shared.mainMenu else {
                return AnyCodable(["error": "Main menu not available"])
            }
            let items = menu.items.map { menuItemPayload($0, parentPath: []) }
            return AnyCodable(["menuItems": items, "count": items.count] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "click_menu_item",
        description: "Invoke a menu item by title path, for example 'File > Save'.",
        inputSchema: macOSInputSchema([
            "path": ["type": "string", "description": "Menu item path, e.g. 'File > Save'"]
        ], required: ["path"]),
        handler: { params in
            guard let rawPath = params?["path"]?.stringValue else {
                return AnyCodable(["error": "path required"])
            }
            let windowId = params?["window_id"]?.stringValue
            _ = focusWindowRef(windowId: windowId, requireExplicitId: false)

            let segments = rawPath
                .split(separator: ">")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !segments.isEmpty else {
                return AnyCodable(["error": "Invalid menu path"])
            }

            guard let menu = NSApplication.shared.mainMenu else {
                return AnyCodable(["error": "Main menu not available"])
            }

            guard let match = findMenuItem(path: segments, in: menu) else {
                return AnyCodable(["error": "Menu item not found: \(rawPath)"])
            }

            guard !match.item.isSeparatorItem else {
                return AnyCodable(["error": "Cannot click a separator"])
            }

            guard match.item.isEnabled else {
                return AnyCodable(["error": "Menu item disabled: \(rawPath)"])
            }

            if match.item.submenu != nil && match.item.action == nil {
                return AnyCodable(["error": "Menu path points to a submenu, not an actionable item"])
            }

            match.menu.performActionForItem(at: match.index)
            return AnyCodable(["success": true, "path": rawPath] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "focus_window",
        description: "Bring a window to the front and make it key.",
        inputSchema: macOSInputSchema(required: ["window_id"]),
        handler: { params in
            guard let windowId = params?["window_id"]?.stringValue else {
                return AnyCodable(["error": "window_id required"])
            }
            guard let ref = focusWindowRef(windowId: windowId, requireExplicitId: true) else {
                return AnyCodable(["error": "Window not found: \(windowId)"])
            }
            return AnyCodable(["success": true, "window_id": ref.id, "title": ref.title] as [String: Any])
        }
    ))
}

@MainActor
func registerMacOSWebViewTools() {
    let router = MCPRouter.shared
    let bridge = MacOSWebViewBridge.shared

    router.register(MCPToolDefinition(
        name: "get_webviews",
        description: "List all WKWebView instances on the current screen with URL, title, loading state, and frame",
        inputSchema: macOSInputSchema(),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            let info = bridge.webViewInfo(windowId: windowId)
            return AnyCodable(["webviews": info, "count": info.count] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_tree",
        description: "Get the DOM tree of a web view. Returns full or partial DOM structure as JSON.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
            "root": ["type": "string", "description": "CSS selector for subtree root (default: body)"],
            "max_depth": ["type": "integer", "description": "Max tree depth (default: 30)"],
            "visible_only": ["type": "boolean", "description": "Only visible elements (default: false)"]
        ]),
        handler: { params in
            let js = DOMSerializer.dumpTreeJS(
                root: params?["root"]?.stringValue,
                maxDepth: params?["max_depth"]?.intValue ?? 30,
                visibleOnly: params?["visible_only"]?.boolValue ?? false
            )
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: js, resultKey: "dom")
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_interactive",
        description: "Get all interactive DOM elements (inputs, buttons, links, selects) with their attributes, values, and selectors",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.interactiveJS())
        }
    ))

    router.register(MCPToolDefinition(
        name: "query_dom",
        description: "Query the DOM with a CSS selector. Returns matching elements with tag, text, attributes, rect.",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"],
            "limit": ["type": "integer", "description": "Max results (default: 50)"]
        ], required: ["selector"]),
        handler: { params in
            guard let selector = params?["selector"]?.stringValue else {
                return AnyCodable(["error": "selector required"])
            }
            let js = DOMSerializer.queryJS(selector: selector, limit: params?["limit"]?.intValue ?? 50)
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: js)
        }
    ))

    router.register(MCPToolDefinition(
        name: "find_dom_text",
        description: "Find DOM elements containing specific text",
        inputSchema: macOSInputSchema([
            "text": ["type": "string", "description": "Text to search for"],
            "tag": ["type": "string", "description": "Optional tag filter (e.g. 'button', 'a')"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["text"]),
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "text required"])
            }
            let js = DOMSerializer.findTextJS(text: text, tag: params?["tag"]?.stringValue)
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: js)
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_click",
        description: "Click a DOM element by CSS selector",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["selector"]),
        handler: { params in
            guard let selector = params?["selector"]?.stringValue else {
                return AnyCodable(["error": "selector required"])
            }
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.clickJS(selector: selector))
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_type",
        description: "Type text into a DOM input or textarea by CSS selector",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector"],
            "text": ["type": "string", "description": "Text to type"],
            "clear": ["type": "boolean", "description": "Clear field first (default: false)"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["selector", "text"]),
        handler: { params in
            guard let selector = params?["selector"]?.stringValue,
                  let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "selector and text required"])
            }
            let js = DOMSerializer.typeJS(
                selector: selector,
                text: text,
                clear: params?["clear"]?.boolValue ?? false
            )
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: js)
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_select",
        description: "Select an option in a dropdown by CSS selector",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector for the select element"],
            "value": ["type": "string", "description": "Option value to select"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["selector", "value"]),
        handler: { params in
            guard let selector = params?["selector"]?.stringValue,
                  let value = params?["value"]?.stringValue else {
                return AnyCodable(["error": "selector and value required"])
            }
            return await evaluateMacOSWebView(
                bridge: bridge,
                params: params,
                js: DOMSerializer.selectJS(selector: selector, value: value)
            )
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_toggle",
        description: "Check or uncheck a checkbox/radio by CSS selector",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector"],
            "checked": ["type": "boolean", "description": "Desired checked state"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["selector", "checked"]),
        handler: { params in
            guard let selector = params?["selector"]?.stringValue,
                  let checked = params?["checked"]?.boolValue else {
                return AnyCodable(["error": "selector and checked required"])
            }
            return await evaluateMacOSWebView(
                bridge: bridge,
                params: params,
                js: DOMSerializer.toggleJS(selector: selector, checked: checked)
            )
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_scroll_to",
        description: "Scroll a web view until a DOM element is visible",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["selector"]),
        handler: { params in
            guard let selector = params?["selector"]?.stringValue else {
                return AnyCodable(["error": "selector required"])
            }
            return await evaluateMacOSWebView(
                bridge: bridge,
                params: params,
                js: DOMSerializer.scrollToJS(selector: selector)
            )
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_evaluate",
        description: "Run arbitrary JavaScript in a web view and return the result",
        inputSchema: macOSInputSchema([
            "javascript": ["type": "string", "description": "JavaScript to evaluate"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["javascript"]),
        handler: { params in
            guard let js = params?["javascript"]?.stringValue else {
                return AnyCodable(["error": "javascript required"])
            }
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: js)
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_navigate",
        description: "Navigate a web view to a URL",
        inputSchema: macOSInputSchema([
            "url": ["type": "string", "description": "URL to navigate to"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ], required: ["url"]),
        handler: { params in
            guard let urlString = params?["url"]?.stringValue,
                  let url = URL(string: urlString) else {
                return AnyCodable(["error": "Invalid URL"])
            }
            let windowId = params?["window_id"]?.stringValue
            guard let webView = bridge.resolveWebView(
                id: params?["webview_id"]?.stringValue,
                windowId: windowId
            ) else {
                return AnyCodable(["error": "WebView not found"])
            }
            webView.load(URLRequest(url: url))
            return AnyCodable(["success": true, "url": urlString] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_back",
        description: "Go back in web view history",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            guard let webView = bridge.resolveWebView(
                id: params?["webview_id"]?.stringValue,
                windowId: windowId
            ) else {
                return AnyCodable(["error": "WebView not found"])
            }
            guard webView.canGoBack else {
                return AnyCodable(["error": "Cannot go back"])
            }
            webView.goBack()
            return AnyCodable(["success": true] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "web_forward",
        description: "Go forward in web view history",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            guard let webView = bridge.resolveWebView(
                id: params?["webview_id"]?.stringValue,
                windowId: windowId
            ) else {
                return AnyCodable(["error": "WebView not found"])
            }
            guard webView.canGoForward else {
                return AnyCodable(["error": "Cannot go forward"])
            }
            webView.goForward()
            return AnyCodable(["success": true] as [String: Any])
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_links",
        description: "Get all links on the page -- just text and href. Minimal tokens.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.linksJS())
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_text",
        description: "Get visible text content of the page stripped of all markup. Optionally scope to a CSS selector. Minimal tokens.",
        inputSchema: macOSInputSchema([
            "selector": ["type": "string", "description": "CSS selector to scope text extraction (default: body)"],
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            let js = DOMSerializer.textContentJS(selector: params?["selector"]?.stringValue)
            return await evaluateMacOSWebView(bridge: bridge, params: params, js: js)
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_forms",
        description: "Get all forms and their fields with types, names, values, options, and selectors. Includes pages without <form> tags.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.formsJS())
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_headings",
        description: "Get all headings (h1-h6) for page structure overview. Minimal tokens.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.headingsJS())
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_images",
        description: "Get all visible images with src, alt text, and dimensions.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.imagesJS())
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_tables",
        description: "Get all tables with headers and row data.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.tablesJS())
        }
    ))

    router.register(MCPToolDefinition(
        name: "get_dom_summary",
        description: "Get a compact page summary: title, meta, headings (h1-h3), element counts (links, images, inputs, buttons), and form overview. Cheapest way to understand a page.",
        inputSchema: macOSInputSchema([
            "webview_id": ["type": "string", "description": "Web view ID (default: first on screen)"]
        ]),
        handler: { params in
            await evaluateMacOSWebView(bridge: bridge, params: params, js: DOMSerializer.summaryJS())
        }
    ))
}

private let macOSWindowIdProperty: [String: Any] = [
    "type": "string",
    "description": "Target window ID from list_windows (default: key window)"
]

private func macOSInputSchema(
    _ properties: [String: Any] = [:],
    required: [String] = []
) -> [String: AnyCodable] {
    var mergedProperties = properties
    mergedProperties["window_id"] = macOSWindowIdProperty

    var schema: [String: AnyCodable] = [
        "type": AnyCodable("object"),
        "properties": AnyCodable(mergedProperties)
    ]

    if !required.isEmpty {
        schema["required"] = AnyCodable(required)
    }

    return schema
}

@MainActor
private func evaluateMacOSWebView(
    bridge: MacOSWebViewBridge,
    params: [String: AnyCodable]?,
    js: String,
    resultKey: String = "result"
) async -> AnyCodable {
    let windowId = params?["window_id"]?.stringValue
    do {
        let result = try await bridge.evaluate(
            js: js,
            webViewId: params?["webview_id"]?.stringValue,
            windowId: windowId
        )
        return AnyCodable([resultKey: result] as [String: Any])
    } catch {
        return AnyCodable(["error": error.localizedDescription])
    }
}

@MainActor
private func focusWindowRef(windowId: String?, requireExplicitId: Bool) -> WindowRef? {
    let ref: WindowRef?
    if requireExplicitId {
        guard let windowId else { return nil }
        ref = platformWindowProvider.window(id: windowId)
    } else {
        ref = platformWindowProvider.resolve(windowId: windowId)
    }

    guard let ref else { return nil }

    NSApplication.shared.activate(ignoringOtherApps: true)
    if ref.nativeWindow.isMiniaturized {
        ref.nativeWindow.deminiaturize(nil)
    }
    ref.nativeWindow.makeKeyAndOrderFront(nil)
    return ref
}

private func menuItemPayload(_ item: NSMenuItem, parentPath: [String]) -> [String: Any] {
    let title = item.title
    let currentPath = title.isEmpty ? parentPath : parentPath + [title]
    var payload: [String: Any] = [
        "title": title,
        "shortcut": shortcutString(for: item),
        "enabled": item.isEnabled,
        "isSeparator": item.isSeparatorItem,
        "path": currentPath.joined(separator: " > ")
    ]

    if let submenu = item.submenu {
        payload["children"] = submenu.items.map { menuItemPayload($0, parentPath: currentPath) }
    }

    return payload
}

private func shortcutString(for item: NSMenuItem) -> String {
    let key = item.keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return "" }

    var parts: [String] = []
    let modifiers = item.keyEquivalentModifierMask

    if modifiers.contains(.control) { parts.append("Ctrl") }
    if modifiers.contains(.option) { parts.append("Opt") }
    if modifiers.contains(.shift) { parts.append("Shift") }
    if modifiers.contains(.command) { parts.append("Cmd") }

    parts.append(key.count == 1 ? key.uppercased() : key)
    return parts.joined(separator: "+")
}

private func findMenuItem(path: [String], in menu: NSMenu) -> (menu: NSMenu, index: Int, item: NSMenuItem)? {
    guard let first = path.first else { return nil }

    for (index, item) in menu.items.enumerated() where menuTitle(item.title) == menuTitle(first) {
        if path.count == 1 {
            return (menu, index, item)
        }

        guard let submenu = item.submenu else { continue }
        if let nested = findMenuItem(path: Array(path.dropFirst()), in: submenu) {
            return nested
        }
    }

    return nil
}

private func menuTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

#endif
#endif
