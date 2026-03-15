// Registers all built-in MCP tools with the router

import Foundation
import UIKit

#if DEBUG

@MainActor
func registerBuiltInTools() {
    let router = MCPRouter.shared

    // MARK: - get_screen

    router.register(MCPToolDefinition(
        name: "get_screen",
        description: "Get the currently active screen identity and metadata",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            let info = ScreenResolver.shared.resolve()
            return AnyCodable([
                "screenKey": info.screenKey,
                "screenTitle": info.screenTitle,
                "frameworkType": info.frameworkType,
                "controllerChain": info.controllerChain,
                "activeTab": info.activeTab as Any,
                "navigationDepth": info.navigationDepth,
                "presentedModals": info.presentedModals,
                "confidence": info.confidence
            ] as [String: Any])
        }
    ))

    // MARK: - get_elements

    router.register(MCPToolDefinition(
        name: "get_elements",
        description: "List all visible interactive elements on the current screen",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            let elements = ElementInventory.shared.listElements()
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
                    "actions": el.actions.joined(separator: ",")
                ] as [String: String]
            }
            return AnyCodable(["screenKey": ScreenResolver.shared.resolve().screenKey, "elements": list] as [String: Any])
        }
    ))

    // MARK: - screenshot

    router.register(MCPToolDefinition(
        name: "screenshot",
        description: "Capture a screenshot of the current screen. Returns base64-encoded image.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "element_id": ["type": "string", "description": "Optional element ID to crop to"],
                "format": ["type": "string", "enum": ["png", "jpeg"], "description": "Image format (default: png)"]
            ] as [String: Any])
        ],
        handler: { params in
            let format: ImageFormat = params?["format"]?.stringValue == "jpeg" ? .jpeg : .png
            let result: ScreenshotCapture.CaptureResult?

            if let elementId = params?["element_id"]?.stringValue {
                result = ScreenshotCapture.shared.captureElement(id: elementId, format: format)
            } else {
                result = ScreenshotCapture.shared.captureScreen(format: format)
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

    // MARK: - tap_element

    router.register(MCPToolDefinition(
        name: "tap_element",
        description: "Tap an element by its accessibility identifier",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["element_id": ["type": "string", "description": "Accessibility identifier"]] as [String: Any]),
            "required": AnyCodable(["element_id"])
        ],
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            do {
                try InteractionEngine.shared.tap(elementId: elementId)
                return AnyCodable(["success": true, "element_id": elementId] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - tap_point

    router.register(MCPToolDefinition(
        name: "tap_point",
        description: "Tap at specific screen coordinates",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["x": ["type": "number"], "y": ["type": "number"]] as [String: Any]),
            "required": AnyCodable(["x", "y"])
        ],
        handler: { params in
            let x = params?["x"]?.doubleValue ?? 0
            let y = params?["y"]?.doubleValue ?? 0
            InteractionEngine.shared.tap(point: CGPoint(x: x, y: y))
            return AnyCodable(["success": true, "x": x, "y": y] as [String: Any])
        }
    ))

    // MARK: - type_text

    router.register(MCPToolDefinition(
        name: "type_text",
        description: "Type text into a text field",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "text": ["type": "string", "description": "Text to type"],
                "element_id": ["type": "string", "description": "Optional target element ID"]
            ] as [String: Any]),
            "required": AnyCodable(["text"])
        ],
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "text required"])
            }
            do {
                try InteractionEngine.shared.type(text: text, elementId: params?["element_id"]?.stringValue)
                return AnyCodable(["success": true, "text": text] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - clear_text

    router.register(MCPToolDefinition(
        name: "clear_text",
        description: "Clear a text field",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["element_id": ["type": "string"]] as [String: Any]),
            "required": AnyCodable(["element_id"])
        ],
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            do {
                try InteractionEngine.shared.clear(elementId: elementId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - scroll

    router.register(MCPToolDefinition(
        name: "scroll",
        description: "Scroll a container in a direction",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
                "container_id": ["type": "string", "description": "Optional scroll view ID"]
            ] as [String: Any]),
            "required": AnyCodable(["direction"])
        ],
        handler: { params in
            guard let dirStr = params?["direction"]?.stringValue,
                  let direction = ScrollDirection(rawValue: dirStr) else {
                return AnyCodable(["error": "Invalid direction"])
            }
            do {
                try InteractionEngine.shared.scroll(direction: direction, containerId: params?["container_id"]?.stringValue)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - scroll_to_element

    router.register(MCPToolDefinition(
        name: "scroll_to_element",
        description: "Scroll until an element is visible",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["element_id": ["type": "string"]] as [String: Any]),
            "required": AnyCodable(["element_id"])
        ],
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            do {
                try InteractionEngine.shared.scrollTo(elementId: elementId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_state

    router.register(MCPToolDefinition(
        name: "get_state",
        description: "Get the current app state snapshot",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable(StateBridge.shared.getState())
        }
    ))

    // MARK: - get_navigation_stack

    router.register(MCPToolDefinition(
        name: "get_navigation_stack",
        description: "Get the current navigation state",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable(StateBridge.shared.getNavigationStack())
        }
    ))

    // MARK: - get_feature_flags

    router.register(MCPToolDefinition(
        name: "get_feature_flags",
        description: "Get all active feature flags",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable(StateBridge.shared.getFeatureFlags())
        }
    ))

    // MARK: - get_network_calls

    router.register(MCPToolDefinition(
        name: "get_network_calls",
        description: "Get recent network calls",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["limit": ["type": "integer", "description": "Max results (default 50)"]] as [String: Any])
        ],
        handler: { params in
            let limit = params?["limit"]?.intValue ?? 50
            let calls = NetworkObserverService.shared.recentCalls(limit: limit)
            let list = calls.map { call in
                [
                    "id": call.id,
                    "method": call.method,
                    "url": call.url,
                    "statusCode": call.statusCode.map { String($0) } ?? "nil",
                    "duration": call.duration.map { String(format: "%.3fs", $0) } ?? "nil",
                    "error": call.error ?? ""
                ]
            }
            return AnyCodable(["calls": list, "count": list.count] as [String: Any])
        }
    ))

    // MARK: - select_tab

    router.register(MCPToolDefinition(
        name: "select_tab",
        description: "Switch to a tab by index (0-based)",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["index": ["type": "integer", "description": "Tab index (0-based)"]] as [String: Any]),
            "required": AnyCodable(["index"])
        ],
        handler: { params in
            guard let index = params?["index"]?.intValue else {
                return AnyCodable(["error": "index required"])
            }
            do {
                try InteractionEngine.shared.selectTab(index: index)
                return AnyCodable(["success": true, "tab_index": index] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - navigate_back

    router.register(MCPToolDefinition(
        name: "navigate_back",
        description: "Pop the current navigation stack",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            do {
                try InteractionEngine.shared.navigateBack()
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - dismiss_modal

    router.register(MCPToolDefinition(
        name: "dismiss_modal",
        description: "Dismiss the topmost presented modal",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            do {
                try InteractionEngine.shared.dismissModal()
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - open_deeplink

    router.register(MCPToolDefinition(
        name: "open_deeplink",
        description: "Open a deep link URL in the app",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable(["url": ["type": "string", "description": "Deep link URL"]] as [String: Any]),
            "required": AnyCodable(["url"])
        ],
        handler: { params in
            guard let urlStr = params?["url"]?.stringValue,
                  let url = URL(string: urlStr) else {
                return AnyCodable(["error": "Invalid URL"])
            }
            await UIApplication.shared.open(url)
            return AnyCodable(["success": true, "url": urlStr] as [String: Any])
        }
    ))

    // MARK: - get_logs

    router.register(MCPToolDefinition(
        name: "get_logs",
        description: "Get recent app logs",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "subsystem": ["type": "string", "description": "Filter by subsystem"],
                "limit": ["type": "integer", "description": "Max results (default 50)"]
            ] as [String: Any])
        ],
        handler: { params in
            let logs = DiagnosticsBridge.shared.getRecentLogs(
                subsystem: params?["subsystem"]?.stringValue,
                limit: params?["limit"]?.intValue ?? 50
            )
            let list = logs.map { log in
                [
                    "timestamp": log.timestamp.ISO8601Format(),
                    "subsystem": log.subsystem,
                    "category": log.category,
                    "level": log.level,
                    "message": log.message
                ]
            }
            return AnyCodable(["logs": list, "count": list.count] as [String: Any])
        }
    ))

    // MARK: - get_recent_errors

    router.register(MCPToolDefinition(
        name: "get_recent_errors",
        description: "Get recent app errors",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            let errors = DiagnosticsBridge.shared.getRecentErrors()
            let list = errors.map { err in
                [
                    "timestamp": err.timestamp.ISO8601Format(),
                    "domain": err.domain,
                    "message": err.message,
                    "stackTrace": err.stackTrace ?? ""
                ]
            }
            return AnyCodable(["errors": list, "count": list.count] as [String: Any])
        }
    ))

    // MARK: - launch_context

    router.register(MCPToolDefinition(
        name: "launch_context",
        description: "Get app launch environment info",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable([
                "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                "platform": "iOS",
                "systemVersion": UIDevice.current.systemVersion,
                "deviceModel": UIDevice.current.model,
                "deviceName": UIDevice.current.name
            ] as [String: Any])
        }
    ))
}

#endif
