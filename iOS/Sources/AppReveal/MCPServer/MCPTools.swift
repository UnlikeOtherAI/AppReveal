// Registers all built-in MCP tools with the router

import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

@MainActor
func registerBuiltInTools() {
    let router = MCPRouter.shared

    // MARK: - list_windows (cross-platform)

    router.register(MCPToolDefinition(
        name: "list_windows",
        description: "List all visible app windows with IDs, titles, frames, and key status. Use window IDs with other tools to target specific windows.",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            let windows = platformWindowProvider.allWindows()
            let list = windows.map { w in
                [
                    "id": w.id,
                    "title": w.title,
                    "isKey": w.isKey,
                    "frame": "\(Int(w.frame.origin.x)),\(Int(w.frame.origin.y)),\(Int(w.frame.width)),\(Int(w.frame.height))"
                ] as [String: Any]
            }
            return AnyCodable(["windows": list, "count": list.count] as [String: Any])
        }
    ))

    // MARK: - get_state (cross-platform)

    router.register(MCPToolDefinition(
        name: "get_state",
        description: "Get the current app state snapshot",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable(StateBridge.shared.getState())
        }
    ))

    // MARK: - get_navigation_stack (cross-platform)

    router.register(MCPToolDefinition(
        name: "get_navigation_stack",
        description: "Get the current navigation state",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable(StateBridge.shared.getNavigationStack())
        }
    ))

    // MARK: - get_feature_flags (cross-platform)

    router.register(MCPToolDefinition(
        name: "get_feature_flags",
        description: "Get all active feature flags",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            return AnyCodable(StateBridge.shared.getFeatureFlags())
        }
    ))

    // MARK: - get_network_calls (cross-platform)

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

    // MARK: - open_deeplink (cross-platform with conditional impl)

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
            #if os(iOS)
            await UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
            return AnyCodable(["success": true, "url": urlStr] as [String: Any])
        }
    ))

    // MARK: - get_logs (cross-platform)

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

    // MARK: - get_recent_errors (cross-platform)

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

    // MARK: - launch_context (cross-platform with conditional impl)

    router.register(MCPToolDefinition(
        name: "launch_context",
        description: "Get app launch environment info",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            var result: [String: Any] = [
                "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            ]
            #if os(iOS)
            result["platform"] = "iOS"
            result["systemVersion"] = UIDevice.current.systemVersion
            result["deviceModel"] = UIDevice.current.model
            result["deviceName"] = UIDevice.current.name
            #elseif os(macOS)
            result["platform"] = "macOS"
            result["systemVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
            result["deviceModel"] = "Mac"
            result["deviceName"] = Host.current().localizedName ?? "Mac"
            #endif
            return AnyCodable(result)
        }
    ))

    // MARK: - device_info (cross-platform with conditional impl)

    router.register(MCPToolDefinition(
        name: "device_info",
        description: "Return comprehensive device and app information: full Info.plist, device hardware, " +
            "OS, screen, locale, timezone, battery, memory, processor, and entitlements. " +
            "Single call to get everything an agent needs to understand the runtime environment.",
        inputSchema: ["type": AnyCodable("object"), "properties": AnyCodable([String: Any]())],
        handler: { _ in
            let processInfo = ProcessInfo.processInfo
            let locale = Locale.current
            let timeZone = TimeZone.current
            let bundle = Bundle.main
            let info = bundle.infoDictionary ?? [:]

            // Full Info.plist -- convert all values to strings for safe serialisation
            var plist: [String: String] = [:]
            for (k, v) in info {
                plist[k] = "\(v)"
            }

            // Memory
            let physicalMemoryMB = Int(processInfo.physicalMemory / 1_048_576)

            // Disk
            let fileManager = FileManager.default
            var diskFreeBytes: Int64 = -1
            var diskTotalBytes: Int64 = -1
            if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
                diskFreeBytes  = (attrs[.systemFreeSize]  as? NSNumber)?.int64Value ?? -1
                diskTotalBytes = (attrs[.systemSize]      as? NSNumber)?.int64Value ?? -1
            }

            // Shared fields
            var result: [String: Any] = [
                // App identity
                "bundleId":      info["CFBundleIdentifier"] as? String ?? "unknown",
                "appName":       info["CFBundleName"] as? String ?? info["CFBundleDisplayName"] as? String ?? "unknown",
                "displayName":   info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "unknown",
                "version":       info["CFBundleShortVersionString"] as? String ?? "unknown",
                "build":         info["CFBundleVersion"] as? String ?? "unknown",
                "executableName": info["CFBundleExecutable"] as? String ?? "unknown",
                "bundlePackageType": info["CFBundlePackageType"] as? String ?? "unknown",

                // OS & process
                "osVersionString":   processInfo.operatingSystemVersionString,
                "osVersion": [
                    "major": processInfo.operatingSystemVersion.majorVersion,
                    "minor": processInfo.operatingSystemVersion.minorVersion,
                    "patch": processInfo.operatingSystemVersion.patchVersion
                ] as [String: Any],
                "processName":       processInfo.processName,
                "processId":         processInfo.processIdentifier,
                "hostName":          processInfo.hostName,
                "processorCount":    processInfo.processorCount,
                "activeProcessorCount": processInfo.activeProcessorCount,
                "physicalMemoryMB":  physicalMemoryMB,
                "isLowPowerMode":    processInfo.isLowPowerModeEnabled,
                "thermalState":      {
                    switch processInfo.thermalState {
                    case .nominal:   return "nominal"
                    case .fair:      return "fair"
                    case .serious:   return "serious"
                    case .critical:  return "critical"
                    @unknown default: return "unknown"
                    }
                }(),

                // Locale & timezone
                "locale": [
                    "identifier":     locale.identifier,
                    "languageCode":   locale.language.languageCode?.identifier ?? "",
                    "regionCode":     locale.region?.identifier ?? "",
                    "currencyCode":   locale.currency?.identifier ?? "",
                    "usesMetricSystem": (locale as NSLocale).object(forKey: .measurementSystem) as? String == "Metric"
                ] as [String: Any],
                "timeZone": [
                    "identifier":       timeZone.identifier,
                    "abbreviation":     timeZone.abbreviation() ?? "",
                    "secondsFromGMT":   timeZone.secondsFromGMT()
                ] as [String: Any],

                // Disk
                "disk": [
                    "freeMB":  diskFreeBytes  >= 0 ? Int(diskFreeBytes  / 1_048_576) : -1,
                    "totalMB": diskTotalBytes >= 0 ? Int(diskTotalBytes / 1_048_576) : -1
                ] as [String: Any],

                // Declared permissions (keys only -- whether granted is runtime)
                "declaredPermissions": info.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") },

                // Full Info.plist
                "infoPlist": plist
            ]

            #if os(iOS)
            let device = UIDevice.current
            let screen = UIScreen.main

            // Battery
            device.isBatteryMonitoringEnabled = true
            let batteryLevel = device.batteryLevel  // 0.0-1.0, -1 if unknown
            let batteryState: String
            switch device.batteryState {
            case .charging: batteryState = "charging"
            case .full:     batteryState = "full"
            case .unplugged: batteryState = "unplugged"
            default:        batteryState = "unknown"
            }
            device.isBatteryMonitoringEnabled = false

            // Idiom
            let idiom: String
            switch device.userInterfaceIdiom {
            case .phone:   idiom = "phone"
            case .pad:     idiom = "pad"
            case .mac:     idiom = "mac"
            case .tv:      idiom = "tv"
            case .carPlay: idiom = "carPlay"
            default:       idiom = "unspecified"
            }

            result["platform"] = "iOS"
            result["frameworkType"] = "uikit"
            result["minOSVersion"] = info["MinimumOSVersion"] as? String ?? "unknown"
            result["deviceModel"] = device.model
            result["deviceName"] = device.name
            result["systemName"] = device.systemName
            result["systemVersion"] = device.systemVersion
            result["userInterfaceIdiom"] = idiom
            result["identifierForVendor"] = device.identifierForVendor?.uuidString ?? "unknown"
            result["isSimulator"] = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
            result["screen"] = [
                "width":          Int(screen.bounds.width),
                "height":         Int(screen.bounds.height),
                "scale":          screen.scale,
                "nativeWidth":    Int(screen.nativeBounds.width),
                "nativeHeight":   Int(screen.nativeBounds.height),
                "nativeScale":    screen.nativeScale,
                "brightness":     screen.brightness
            ] as [String: Any]
            result["battery"] = [
                "level": batteryLevel >= 0 ? batteryLevel : nil as Float?,
                "state": batteryState
            ] as [String: Any?]
            #elseif os(macOS)
            result["platform"] = "macOS"
            result["frameworkType"] = "appkit"
            result["minOSVersion"] = info["LSMinimumSystemVersion"] as? String ?? "unknown"
            result["deviceModel"] = "Mac"
            result["deviceName"] = Host.current().localizedName ?? "Mac"
            result["systemName"] = "macOS"
            result["systemVersion"] = processInfo.operatingSystemVersionString
            if let screen = NSScreen.main {
                result["screen"] = [
                    "width":          Int(screen.frame.width),
                    "height":         Int(screen.frame.height),
                    "scale":          screen.backingScaleFactor,
                    "visibleWidth":   Int(screen.visibleFrame.width),
                    "visibleHeight":  Int(screen.visibleFrame.height)
                ] as [String: Any]
            }
            #endif

            return AnyCodable(result)
        }
    ))

    // MARK: - batch (cross-platform)

    router.register(MCPToolDefinition(
        name: "batch",
        description: "Execute multiple tool calls in a single request. Actions run sequentially. " +
            "Each action can have an optional delay_ms (milliseconds to wait BEFORE executing that action) " +
            "to account for animations, screen transitions, or loading. Returns results for every action.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "actions": [
                    "type": "array",
                    "description": "Array of actions. Each: {\"tool\": \"tool_name\", \"arguments\": {...}, \"delay_ms\": 500}",
                    "items": [
                        "type": "object",
                        "properties": [
                            "tool": ["type": "string", "description": "Tool name"],
                            "arguments": ["type": "object", "description": "Tool arguments"],
                            "delay_ms": ["type": "integer", "description": "Milliseconds to wait before this action (for animations/transitions)"]
                        ],
                        "required": ["tool"]
                    ]
                ],
                "stop_on_error": [
                    "type": "boolean",
                    "description": "Stop executing remaining actions if one fails (default: false)"
                ]
            ] as [String: Any]),
            "required": AnyCodable(["actions"])
        ],
        handler: { params in
            guard let actionsRaw = params?["actions"]?.arrayValue else {
                return AnyCodable(["error": "actions array required"])
            }

            let stopOnError = params?["stop_on_error"]?.boolValue ?? false
            var results: [[String: Any]] = []

            for (index, actionRaw) in actionsRaw.enumerated() {
                guard let action = actionRaw as? [String: Any],
                      let toolName = action["tool"] as? String else {
                    results.append(["index": index, "error": "Invalid action format"])
                    if stopOnError { break }
                    continue
                }

                // Delay before this action
                if let delayMs = action["delay_ms"] as? Int, delayMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                }

                guard let tool = router.tool(named: toolName) else {
                    results.append(["index": index, "tool": toolName, "error": "Tool not found"])
                    if stopOnError { break }
                    continue
                }

                let arguments: [String: AnyCodable]?
                if let args = action["arguments"] as? [String: Any] {
                    arguments = args.mapValues { AnyCodable($0) }
                } else {
                    arguments = nil
                }

                do {
                    let result = try await tool.handler(arguments)
                    let resultData = try JSONEncoder().encode(result)
                    let resultString = String(data: resultData, encoding: .utf8) ?? "{}"
                    results.append(["index": index, "tool": toolName, "result": resultString])
                } catch {
                    results.append(["index": index, "tool": toolName, "error": error.localizedDescription])
                    if stopOnError { break }
                }
            }

            return AnyCodable(["results": results, "count": results.count] as [String: Any])
        }
    ))

    // Register platform-specific UI tools
    #if os(iOS)
    registerIOSBuiltInTools()
    #elseif os(macOS)
    registerMacOSBuiltInTools()
    #endif
}

// MARK: - iOS-specific tools

#if os(iOS)

@MainActor
private func registerIOSBuiltInTools() {
    let router = MCPRouter.shared

    // MARK: - get_screen

    router.register(MCPToolDefinition(
        name: "get_screen",
        description: "Get the currently active screen identity and metadata",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            let info = ScreenResolver.shared.resolve(windowId: windowId)
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

    // MARK: - get_elements

    router.register(MCPToolDefinition(
        name: "get_elements",
        description: "List all visible interactive elements on the current screen. Elements include an idSource " +
            "field showing how the ID was derived: explicit (accessibilityIdentifier), " +
            "semantics (accessibilityLabel), text (visible text), or derived (fallback).",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
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
                "format": ["type": "string", "enum": ["png", "jpeg"], "description": "Image format (default: png)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let format: ImageFormat = params?["format"]?.stringValue == "jpeg" ? .jpeg : .png
            let windowId = params?["window_id"]?.stringValue
            let result: ScreenshotCapture.CaptureResult?

            if let elementId = params?["element_id"]?.stringValue {
                result = ScreenshotCapture.shared.captureElement(id: elementId, format: format, windowId: windowId)
            } else {
                result = ScreenshotCapture.shared.captureScreen(format: format, windowId: windowId)
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
        description: "Tap an element by ID. Resolves by accessibilityIdentifier, accessibilityLabel, " +
            "derived text ID, or visible text (in that order). If not found, try tap_text for direct text targeting.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "element_id": ["type": "string", "description": "Element ID (accessibilityIdentifier, derived text ID, or visible text)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["element_id"])
        ],
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.tap(elementId: elementId, windowId: windowId)
                return AnyCodable(["success": true, "element_id": elementId] as [String: Any])
            } catch {
                return AnyCodable(["error": "\(error.localizedDescription). Try tap_text for visible text targeting, or get_elements to list available IDs."])
            }
        }
    ))

    // MARK: - tap_text

    router.register(MCPToolDefinition(
        name: "tap_text",
        description: "Tap the nearest tappable element containing the given visible text. Use when you know what text is on screen but not the element ID.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "text": ["type": "string", "description": "Visible text to find and tap"],
                "match_mode": ["type": "string", "enum": ["exact", "contains"], "description": "Match mode (default: exact)"],
                "occurrence": ["type": "integer", "description": "0-based index when multiple matches exist"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["text"])
        ],
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

            // Tap the resolved view
            let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            InteractionEngine.shared.tap(point: center, windowId: windowId)
            return AnyCodable(["success": true, "text": text] as [String: Any])
        }
    ))

    // MARK: - tap_point

    router.register(MCPToolDefinition(
        name: "tap_point",
        description: "Tap at specific screen coordinates",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "x": ["type": "number"],
                "y": ["type": "number"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["x", "y"])
        ],
        handler: { params in
            let x = params?["x"]?.doubleValue ?? 0
            let y = params?["y"]?.doubleValue ?? 0
            let windowId = params?["window_id"]?.stringValue
            InteractionEngine.shared.tap(point: CGPoint(x: x, y: y), windowId: windowId)
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
                "element_id": ["type": "string", "description": "Optional target element ID"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["text"])
        ],
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return AnyCodable(["error": "text required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.type(text: text, elementId: params?["element_id"]?.stringValue, windowId: windowId)
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
            "properties": AnyCodable([
                "element_id": ["type": "string"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["element_id"])
        ],
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.clear(elementId: elementId, windowId: windowId)
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
                "container_id": ["type": "string", "description": "Optional scroll view ID"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["direction"])
        ],
        handler: { params in
            guard let dirStr = params?["direction"]?.stringValue,
                  let direction = ScrollDirection(rawValue: dirStr) else {
                return AnyCodable(["error": "Invalid direction"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.scroll(direction: direction, containerId: params?["container_id"]?.stringValue, windowId: windowId)
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
            "properties": AnyCodable([
                "element_id": ["type": "string"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["element_id"])
        ],
        handler: { params in
            guard let elementId = params?["element_id"]?.stringValue else {
                return AnyCodable(["error": "element_id required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.scrollTo(elementId: elementId, windowId: windowId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - select_tab

    router.register(MCPToolDefinition(
        name: "select_tab",
        description: "Switch to a tab by index (0-based)",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "index": ["type": "integer", "description": "Tab index (0-based)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any]),
            "required": AnyCodable(["index"])
        ],
        handler: { params in
            guard let index = params?["index"]?.intValue else {
                return AnyCodable(["error": "index required"])
            }
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.selectTab(index: index, windowId: windowId)
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
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.navigateBack(windowId: windowId)
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
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let windowId = params?["window_id"]?.stringValue
            do {
                try InteractionEngine.shared.dismissModal(windowId: windowId)
                return AnyCodable(["success": true] as [String: Any])
            } catch {
                return AnyCodable(["error": error.localizedDescription])
            }
        }
    ))

    // MARK: - get_view_tree

    router.register(MCPToolDefinition(
        name: "get_view_tree",
        description: "Dump the full view hierarchy of the current screen. Returns every view with class, frame, properties, accessibility info, and depth. Use for discovering all objects on screen.",
        inputSchema: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "max_depth": ["type": "integer", "description": "Max hierarchy depth (default 50)"],
                "window_id": ["type": "string", "description": "Target window ID from list_windows (default: key window)"]
            ] as [String: Any])
        ],
        handler: { params in
            let maxDepth = params?["max_depth"]?.intValue ?? 50
            let windowId = params?["window_id"]?.stringValue
            let tree = ElementInventory.shared.dumpViewTree(maxDepth: maxDepth, windowId: windowId)
            return AnyCodable(["views": tree, "count": tree.count] as [String: Any])
        }
    ))
}

#elseif os(macOS)

@MainActor
private func registerMacOSBuiltInTools() {
    registerMacOSBuiltInToolsImpl()
}

#endif // os

#endif // DEBUG
