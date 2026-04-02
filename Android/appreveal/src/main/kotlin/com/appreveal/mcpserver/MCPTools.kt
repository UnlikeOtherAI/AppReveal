package com.appreveal.mcpserver

import android.content.Intent
import android.net.Uri
import android.os.Build
import com.appreveal.diagnostics.DiagnosticsBridge
import com.appreveal.elements.ElementInventory
import com.appreveal.interaction.InteractionEngine
import com.appreveal.network.NetworkObserverService
import com.appreveal.screen.ScreenResolver
import com.appreveal.screenshot.ScreenshotCapture
import com.appreveal.state.StateBridge
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject

/**
 * Registers all built-in MCP tools with the router.
 */
internal fun registerBuiltInTools() {
    val router = MCPRouter

    // -- get_screen --

    router.register(
        MCPToolDefinition(
            name = "get_screen",
            description = "Get the currently active screen identity and metadata",
            inputSchema = jsonSchema(),
            handler = { _ ->
                val info = ScreenResolver.resolve()
                JsonObject().apply {
                    addProperty("screenKey", info.screenKey)
                    addProperty("screenTitle", info.screenTitle)
                    addProperty("frameworkType", info.frameworkType)
                    add("activityChain", info.activityChain.toJsonArray())
                    addProperty("activeTab", info.activeTab)
                    addProperty("navigationDepth", info.navigationDepth)
                    add("presentedModals", info.presentedModals.toJsonArray())
                    addProperty("confidence", info.confidence)
                    addProperty("source", info.source)
                    addProperty("appBarTitle", info.appBarTitle)
                }
            },
        ),
    )

    // -- get_elements --

    router.register(
        MCPToolDefinition(
            name = "get_elements",
            description = "List all visible interactive elements on the current screen",
            inputSchema = jsonSchema(),
            handler = { _ ->
                val elements = ElementInventory.listElements()
                val screenKey = ScreenResolver.resolve().screenKey
                val list = JsonArray()
                for (el in elements) {
                    list.add(
                        JsonObject().apply {
                            addProperty("id", el.id)
                            addProperty("type", el.type.value)
                            addProperty("label", el.label ?: "")
                            addProperty("value", el.value ?: "")
                            addProperty("enabled", if (el.enabled) "true" else "false")
                            addProperty("visible", if (el.visible) "true" else "false")
                            addProperty("tappable", if (el.tappable) "true" else "false")
                            addProperty("frame", "${el.frame.x.toInt()},${el.frame.y.toInt()},${el.frame.width.toInt()},${el.frame.height.toInt()}")
                            add(
                                "safeAreaInsets",
                                JsonObject().apply {
                                    addProperty("top", el.safeAreaInsets.top)
                                    addProperty("leading", el.safeAreaInsets.leading)
                                    addProperty("bottom", el.safeAreaInsets.bottom)
                                    addProperty("trailing", el.safeAreaInsets.trailing)
                                },
                            )
                            add(
                                "safeAreaLayoutGuideFrame",
                                JsonObject().apply {
                                    addProperty("x", el.safeAreaLayoutGuideFrame.x)
                                    addProperty("y", el.safeAreaLayoutGuideFrame.y)
                                    addProperty("width", el.safeAreaLayoutGuideFrame.width)
                                    addProperty("height", el.safeAreaLayoutGuideFrame.height)
                                },
                            )
                            addProperty("actions", el.actions.joinToString(","))
                            addProperty("idSource", el.idSource)
                        },
                    )
                }
                JsonObject().apply {
                    addProperty("screenKey", screenKey)
                    add("elements", list)
                }
            },
        ),
    )

    // -- get_view_tree --

    router.register(
        MCPToolDefinition(
            name = "get_view_tree",
            description = "Dump the full view hierarchy of the current screen. Returns every view with class, frame, properties, accessibility info, and depth. Use for discovering all objects on screen.",
            inputSchema = jsonSchema("max_depth" to jsonProp("integer", "Max hierarchy depth (default 50)")),
            handler = { params ->
                val maxDepth = params?.get("max_depth")?.asIntOrNull() ?: 50
                val tree = ElementInventory.dumpViewTree(maxDepth)
                JsonObject().apply {
                    add("views", tree.toJsonElement())
                    addProperty("count", tree.size)
                }
            },
        ),
    )

    // -- tap_element --

    router.register(
        MCPToolDefinition(
            name = "tap_element",
            description = "Tap an element by its ID (accessibility identifier, resource name, or derived ID). Falls back to text-based matching if direct ID lookup fails.",
            inputSchema =
                jsonSchema(
                    "element_id" to jsonProp("string", "Element ID (accessibility identifier, resource name, or derived)"),
                    required = listOf("element_id"),
                ),
            handler = { params ->
                val elementId =
                    params?.get("element_id")?.asString
                        ?: return@MCPToolDefinition errorResult("element_id required")
                try {
                    InteractionEngine.tap(elementId)
                    JsonObject().apply {
                        addProperty("success", true)
                        addProperty("element_id", elementId)
                    }
                } catch (e: Exception) {
                    // Try text-based resolution as fallback
                    val textResult = InteractionEngine.tapByText(elementId, "contains")
                    val success = textResult["success"] as? Boolean ?: false
                    if (success) {
                        JsonObject().apply {
                            addProperty("success", true)
                            addProperty("element_id", elementId)
                            addProperty("resolvedVia", "text")
                        }
                    } else {
                        errorResult(e.message ?: "Tap failed")
                    }
                }
            },
        ),
    )

    // -- tap_point --

    router.register(
        MCPToolDefinition(
            name = "tap_point",
            description = "Tap at specific screen coordinates",
            inputSchema =
                jsonSchema(
                    "x" to jsonProp("number"),
                    "y" to jsonProp("number"),
                    required = listOf("x", "y"),
                ),
            handler = { params ->
                val x = params?.get("x")?.asFloat ?: 0f
                val y = params?.get("y")?.asFloat ?: 0f
                InteractionEngine.tap(x, y)
                JsonObject().apply {
                    addProperty("success", true)
                    addProperty("x", x)
                    addProperty("y", y)
                }
            },
        ),
    )

    // -- tap_text --

    router.register(
        MCPToolDefinition(
            name = "tap_text",
            description = "Tap the nearest tappable element containing the given visible text. Use when you know what text is on screen but not the element ID.",
            inputSchema =
                jsonSchema(
                    "text" to jsonProp("string", "Visible text to find and tap"),
                    "match_mode" to jsonProp("string", "Match mode: exact or contains (default: exact)"),
                    "occurrence" to jsonProp("integer", "0-based index when multiple matches exist"),
                    required = listOf("text"),
                ),
            handler = { params ->
                val text =
                    params?.get("text")?.asString
                        ?: return@MCPToolDefinition errorResult("text required")
                val matchMode = params.get("match_mode")?.asStringOrNull() ?: "exact"
                val occurrence = params.get("occurrence")?.asIntOrNull() ?: 0

                val result = InteractionEngine.tapByText(text, matchMode, occurrence)
                val success = result["success"] as? Boolean ?: false

                if (success) {
                    JsonObject().apply {
                        addProperty("success", true)
                        addProperty("tappedText", text)
                        addProperty("matchMode", matchMode)
                        @Suppress("UNCHECKED_CAST")
                        val candidates = result["candidates"] as? List<String> ?: emptyList()
                        add("candidates", candidates.toJsonArray())
                    }
                } else {
                    val error = result["error"] as? String ?: "Tap failed"

                    @Suppress("UNCHECKED_CAST")
                    val candidates = result["candidates"] as? List<String> ?: emptyList()
                    JsonObject().apply {
                        addProperty("error", error)
                        add("candidates", candidates.toJsonArray())
                    }
                }
            },
        ),
    )

    // -- type_text --

    router.register(
        MCPToolDefinition(
            name = "type_text",
            description = "Type text into a text field",
            inputSchema =
                jsonSchema(
                    "text" to jsonProp("string", "Text to type"),
                    "element_id" to jsonProp("string", "Optional target element ID"),
                    required = listOf("text"),
                ),
            handler = { params ->
                val text =
                    params?.get("text")?.asString
                        ?: return@MCPToolDefinition errorResult("text required")
                val elementId = params.get("element_id")?.asStringOrNull()
                try {
                    InteractionEngine.type(text, elementId)
                    JsonObject().apply {
                        addProperty("success", true)
                        addProperty("text", text)
                    }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Type failed")
                }
            },
        ),
    )

    // -- clear_text --

    router.register(
        MCPToolDefinition(
            name = "clear_text",
            description = "Clear a text field",
            inputSchema =
                jsonSchema(
                    "element_id" to jsonProp("string"),
                    required = listOf("element_id"),
                ),
            handler = { params ->
                val elementId =
                    params?.get("element_id")?.asString
                        ?: return@MCPToolDefinition errorResult("element_id required")
                try {
                    InteractionEngine.clear(elementId)
                    JsonObject().apply { addProperty("success", true) }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Clear failed")
                }
            },
        ),
    )

    // -- scroll --

    router.register(
        MCPToolDefinition(
            name = "scroll",
            description = "Scroll a container in a direction",
            inputSchema =
                jsonSchema(
                    "direction" to
                        JsonObject().apply {
                            addProperty("type", "string")
                            add(
                                "enum",
                                JsonArray().apply {
                                    add("up")
                                    add("down")
                                    add("left")
                                    add("right")
                                },
                            )
                        },
                    "container_id" to jsonProp("string", "Optional scroll view ID"),
                    required = listOf("direction"),
                ),
            handler = { params ->
                val direction =
                    params?.get("direction")?.asString
                        ?: return@MCPToolDefinition errorResult("Invalid direction")
                val containerId = params.get("container_id")?.asStringOrNull()
                try {
                    InteractionEngine.scroll(direction, containerId)
                    JsonObject().apply { addProperty("success", true) }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Scroll failed")
                }
            },
        ),
    )

    // -- scroll_to_element --

    router.register(
        MCPToolDefinition(
            name = "scroll_to_element",
            description = "Scroll until an element is visible",
            inputSchema =
                jsonSchema(
                    "element_id" to jsonProp("string"),
                    required = listOf("element_id"),
                ),
            handler = { params ->
                val elementId =
                    params?.get("element_id")?.asString
                        ?: return@MCPToolDefinition errorResult("element_id required")
                try {
                    InteractionEngine.scrollTo(elementId)
                    JsonObject().apply { addProperty("success", true) }
                } catch (e: Exception) {
                    errorResult(e.message ?: "ScrollTo failed")
                }
            },
        ),
    )

    // -- screenshot --

    router.register(
        MCPToolDefinition(
            name = "screenshot",
            description = "Capture a screenshot of the current screen. Returns base64-encoded image.",
            inputSchema =
                jsonSchema(
                    "element_id" to jsonProp("string", "Optional element ID to crop to"),
                    "format" to
                        JsonObject().apply {
                            addProperty("type", "string")
                            add(
                                "enum",
                                JsonArray().apply {
                                    add("png")
                                    add("jpeg")
                                },
                            )
                            addProperty("description", "Image format (default: png)")
                        },
                ),
            handler = { params ->
                val format = params?.get("format")?.asStringOrNull() ?: "png"
                val elementId = params?.get("element_id")?.asStringOrNull()

                val result =
                    if (elementId != null) {
                        ScreenshotCapture.captureElement(elementId, format)
                    } else {
                        ScreenshotCapture.captureScreen(format)
                    }

                if (result == null) {
                    errorResult("Failed to capture screenshot")
                } else {
                    JsonObject().apply {
                        addProperty("image", result.imageData)
                        addProperty("width", result.width)
                        addProperty("height", result.height)
                        addProperty("scale", result.scale)
                        addProperty("format", result.format)
                    }
                }
            },
        ),
    )

    // -- select_tab --

    router.register(
        MCPToolDefinition(
            name = "select_tab",
            description = "Switch to a tab by index (0-based)",
            inputSchema =
                jsonSchema(
                    "index" to jsonProp("integer", "Tab index (0-based)"),
                    required = listOf("index"),
                ),
            handler = { params ->
                val index =
                    params?.get("index")?.asInt
                        ?: return@MCPToolDefinition errorResult("index required")
                try {
                    InteractionEngine.selectTab(index)
                    JsonObject().apply {
                        addProperty("success", true)
                        addProperty("tab_index", index)
                    }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Tab select failed")
                }
            },
        ),
    )

    // -- navigate_back --

    router.register(
        MCPToolDefinition(
            name = "navigate_back",
            description = "Pop the current navigation stack",
            inputSchema = jsonSchema(),
            handler = { _ ->
                try {
                    InteractionEngine.navigateBack()
                    JsonObject().apply { addProperty("success", true) }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Navigate back failed")
                }
            },
        ),
    )

    // -- dismiss_modal --

    router.register(
        MCPToolDefinition(
            name = "dismiss_modal",
            description = "Dismiss the topmost presented modal",
            inputSchema = jsonSchema(),
            handler = { _ ->
                try {
                    InteractionEngine.dismissModal()
                    JsonObject().apply { addProperty("success", true) }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Dismiss failed")
                }
            },
        ),
    )

    // -- open_deeplink --

    router.register(
        MCPToolDefinition(
            name = "open_deeplink",
            description = "Open a deep link URL in the app",
            inputSchema =
                jsonSchema(
                    "url" to jsonProp("string", "Deep link URL"),
                    required = listOf("url"),
                ),
            handler = { params ->
                val urlStr =
                    params?.get("url")?.asString
                        ?: return@MCPToolDefinition errorResult("Invalid URL")
                try {
                    val activity =
                        ScreenResolver.currentActivity
                            ?: return@MCPToolDefinition errorResult("No activity")
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlStr))
                    activity.startActivity(intent)
                    JsonObject().apply {
                        addProperty("success", true)
                        addProperty("url", urlStr)
                    }
                } catch (e: Exception) {
                    errorResult(e.message ?: "Failed to open deeplink")
                }
            },
        ),
    )

    // -- get_state --

    router.register(
        MCPToolDefinition(
            name = "get_state",
            description = "Get the current app state snapshot",
            inputSchema = jsonSchema(),
            handler = { _ ->
                StateBridge.getState().toJsonObject()
            },
        ),
    )

    // -- get_navigation_stack --

    router.register(
        MCPToolDefinition(
            name = "get_navigation_stack",
            description = "Get the current navigation state",
            inputSchema = jsonSchema(),
            handler = { _ ->
                StateBridge.getNavigationStack().toJsonObject()
            },
        ),
    )

    // -- get_feature_flags --

    router.register(
        MCPToolDefinition(
            name = "get_feature_flags",
            description = "Get all active feature flags",
            inputSchema = jsonSchema(),
            handler = { _ ->
                StateBridge.getFeatureFlags().toJsonObject()
            },
        ),
    )

    // -- get_network_calls --

    router.register(
        MCPToolDefinition(
            name = "get_network_calls",
            description = "Get recent network calls",
            inputSchema = jsonSchema("limit" to jsonProp("integer", "Max results (default 50)")),
            handler = { params ->
                val limit = params?.get("limit")?.asIntOrNull() ?: 50
                val calls = NetworkObserverService.recentCalls(limit)
                val list = JsonArray()
                for (call in calls) {
                    list.add(
                        JsonObject().apply {
                            addProperty("id", call.id)
                            addProperty("method", call.method)
                            addProperty("url", call.url)
                            addProperty("statusCode", call.statusCode?.toString() ?: "nil")
                            addProperty("duration", call.duration?.let { String.format("%.3fs", it) } ?: "nil")
                            addProperty("error", call.error ?: "")
                        },
                    )
                }
                JsonObject().apply {
                    add("calls", list)
                    addProperty("count", list.size())
                }
            },
        ),
    )

    // -- get_logs --

    router.register(
        MCPToolDefinition(
            name = "get_logs",
            description = "Get recent app logs",
            inputSchema =
                jsonSchema(
                    "subsystem" to jsonProp("string", "Filter by subsystem"),
                    "limit" to jsonProp("integer", "Max results (default 50)"),
                ),
            handler = { params ->
                val subsystem = params?.get("subsystem")?.asStringOrNull()
                val limit = params?.get("limit")?.asIntOrNull() ?: 50
                val logs = DiagnosticsBridge.getRecentLogs(subsystem, limit)
                val list = JsonArray()
                for (log in logs) {
                    list.add(
                        JsonObject().apply {
                            addProperty("timestamp", log.timestamp)
                            addProperty("subsystem", log.subsystem)
                            addProperty("category", log.category)
                            addProperty("level", log.level)
                            addProperty("message", log.message)
                        },
                    )
                }
                JsonObject().apply {
                    add("logs", list)
                    addProperty("count", list.size())
                }
            },
        ),
    )

    // -- get_recent_errors --

    router.register(
        MCPToolDefinition(
            name = "get_recent_errors",
            description = "Get recent app errors",
            inputSchema = jsonSchema(),
            handler = { _ ->
                val errors = DiagnosticsBridge.getRecentErrors()
                val list = JsonArray()
                for (err in errors) {
                    list.add(
                        JsonObject().apply {
                            addProperty("timestamp", err.timestamp)
                            addProperty("domain", err.domain)
                            addProperty("message", err.message)
                            addProperty("stackTrace", err.stackTrace ?: "")
                        },
                    )
                }
                JsonObject().apply {
                    add("errors", list)
                    addProperty("count", list.size())
                }
            },
        ),
    )

    // -- launch_context --

    router.register(
        MCPToolDefinition(
            name = "launch_context",
            description = "Get app launch environment info",
            inputSchema = jsonSchema(),
            handler = { _ ->
                val app = com.appreveal.AppReveal.application
                val packageName = app?.packageName ?: "unknown"
                val packageInfo =
                    try {
                        app?.packageManager?.getPackageInfo(packageName, 0)
                    } catch (_: Exception) {
                        null
                    }

                JsonObject().apply {
                    addProperty("applicationId", packageName)
                    addProperty("versionName", packageInfo?.versionName ?: "unknown")
                    addProperty("versionCode", packageInfo?.longVersionCode ?: 0L)
                    addProperty("platform", "Android")
                    addProperty("systemVersion", Build.VERSION.RELEASE)
                    addProperty("deviceModel", Build.MODEL)
                    addProperty("deviceName", Build.DEVICE)
                }
            },
        ),
    )

    // -- device_info --

    router.register(
        MCPToolDefinition(
            name = "device_info",
            description =
                "Return comprehensive device and app information: full manifest metadata, device hardware, " +
                    "OS build details, screen metrics, locale, timezone, battery, memory, and storage. " +
                    "Single call to get everything an agent needs to understand the runtime environment.",
            inputSchema = jsonSchema(),
            handler = { _ ->
                val app = com.appreveal.AppReveal.application
                val ctx = app ?: return@MCPToolDefinition JsonObject().apply { addProperty("error", "no application context") }
                val pm = ctx.packageManager
                val packageName = ctx.packageName

                @Suppress("DEPRECATION")
                val pkgInfo =
                    try {
                        pm.getPackageInfo(packageName, android.content.pm.PackageManager.GET_META_DATA)
                    } catch (_: Exception) {
                        null
                    }
                val appInfo = pkgInfo?.applicationInfo

                // Metadata from AndroidManifest
                val metaData = JsonObject()
                appInfo?.metaData?.keySet()?.forEach { key ->
                    metaData.addProperty(key, appInfo.metaData.get(key)?.toString() ?: "")
                }

                // Display metrics
                val dm = ctx.resources.displayMetrics
                val wm = ctx.getSystemService(android.content.Context.WINDOW_SERVICE) as? android.view.WindowManager
                val displaySize = android.graphics.Point()
                @Suppress("DEPRECATION")
                wm?.defaultDisplay?.getRealSize(displaySize)

                // Battery
                val batteryIntent = ctx.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
                val batteryLevel =
                    batteryIntent?.let {
                        val level = it.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
                        val scale = it.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1)
                        if (level >= 0 && scale > 0) level.toFloat() / scale.toFloat() else -1f
                    } ?: -1f
                val batteryPlugged = batteryIntent?.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, -1) ?: -1
                val batteryState =
                    when {
                        batteryPlugged == android.os.BatteryManager.BATTERY_PLUGGED_AC ||
                            batteryPlugged == android.os.BatteryManager.BATTERY_PLUGGED_USB ||
                            batteryPlugged == android.os.BatteryManager.BATTERY_PLUGGED_WIRELESS -> "charging"

                        batteryLevel >= 0.99f -> "full"

                        batteryLevel >= 0f -> "unplugged"

                        else -> "unknown"
                    }

                // Memory
                val actMgr = ctx.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                val memInfo = android.app.ActivityManager.MemoryInfo()
                actMgr?.getMemoryInfo(memInfo)

                // Storage
                val statFs =
                    try {
                        android.os.StatFs(
                            android.os.Environment
                                .getDataDirectory()
                                .path,
                        )
                    } catch (_: Exception) {
                        null
                    }
                val diskFreeMB = statFs?.let { (it.availableBlocksLong * it.blockSizeLong) / 1_048_576 } ?: -1L
                val diskTotalMB = statFs?.let { (it.blockCountLong * it.blockSizeLong) / 1_048_576 } ?: -1L

                // Locale
                @Suppress("DEPRECATION")
                val locale = java.util.Locale.getDefault()

                // Permissions declared in manifest
                val declaredPermissions =
                    try {
                        @Suppress("DEPRECATION")
                        pm
                            .getPackageInfo(packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
                            .requestedPermissions
                            ?.toList() ?: emptyList()
                    } catch (_: Exception) {
                        emptyList()
                    }

                JsonObject().apply {
                    addProperty("platform", "Android")
                    addProperty("frameworkType", "android")

                    // App identity
                    addProperty("applicationId", packageName)
                    addProperty("appName", appInfo?.loadLabel(pm)?.toString() ?: "unknown")
                    addProperty("versionName", pkgInfo?.versionName ?: "unknown")
                    @Suppress("DEPRECATION")
                    addProperty("versionCode", pkgInfo?.longVersionCode ?: 0L)
                    addProperty("targetSdk", appInfo?.targetSdkVersion ?: -1)
                    addProperty("minSdk", appInfo?.minSdkVersion ?: -1)
                    addProperty("firstInstallTime", pkgInfo?.firstInstallTime ?: 0L)
                    addProperty("lastUpdateTime", pkgInfo?.lastUpdateTime ?: 0L)
                    addProperty("isDebuggable", (appInfo?.flags?.and(android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) ?: 0) != 0)
                    add("manifestMetaData", metaData)

                    // Device hardware
                    addProperty("deviceManufacturer", Build.MANUFACTURER)
                    addProperty("deviceModel", Build.MODEL)
                    addProperty("deviceBrand", Build.BRAND)
                    addProperty("deviceDevice", Build.DEVICE)
                    addProperty("deviceProduct", Build.PRODUCT)
                    addProperty("deviceHardware", Build.HARDWARE)
                    addProperty("deviceBoard", Build.BOARD)
                    addProperty("deviceDisplay", Build.DISPLAY)
                    addProperty("deviceFingerprint", Build.FINGERPRINT)
                    addProperty("deviceId", Build.ID)
                    addProperty("deviceHost", Build.HOST)
                    addProperty("deviceUser", Build.USER)
                    addProperty("deviceType", Build.TYPE)
                    addProperty("deviceTags", Build.TAGS)
                    addProperty(
                        "isEmulator",
                        Build.FINGERPRINT.startsWith("generic") ||
                            Build.FINGERPRINT.startsWith("unknown") || Build.MODEL.contains("Emulator") ||
                            Build.MODEL.contains("Android SDK"),
                    )

                    // OS version
                    addProperty("systemVersion", Build.VERSION.RELEASE)
                    addProperty("sdkInt", Build.VERSION.SDK_INT)
                    addProperty("codename", Build.VERSION.CODENAME)
                    addProperty("incremental", Build.VERSION.INCREMENTAL)
                    if (Build.VERSION.SDK_INT >= 23) addProperty("securityPatch", Build.VERSION.SECURITY_PATCH)
                    if (Build.VERSION.SDK_INT >= 33) addProperty("mediaPerformanceClass", Build.VERSION.MEDIA_PERFORMANCE_CLASS)

                    // Screen
                    add(
                        "screen",
                        JsonObject().apply {
                            addProperty("widthPx", displaySize.x.takeIf { it > 0 } ?: dm.widthPixels)
                            addProperty("heightPx", displaySize.y.takeIf { it > 0 } ?: dm.heightPixels)
                            addProperty("density", dm.density)
                            addProperty("densityDpi", dm.densityDpi)
                            addProperty("xdpi", dm.xdpi)
                            addProperty("ydpi", dm.ydpi)
                            addProperty("widthDp", (dm.widthPixels / dm.density).toInt())
                            addProperty("heightDp", (dm.heightPixels / dm.density).toInt())
                        },
                    )

                    // Battery
                    add(
                        "battery",
                        JsonObject().apply {
                            addProperty("level", if (batteryLevel >= 0) batteryLevel else null as Float?)
                            addProperty("state", batteryState)
                        },
                    )

                    // Memory
                    add(
                        "memory",
                        JsonObject().apply {
                            addProperty("totalRamMB", memInfo.totalMem / 1_048_576)
                            addProperty("availableRamMB", memInfo.availMem / 1_048_576)
                            addProperty("isLowMemory", memInfo.lowMemory)
                            addProperty("lowMemThresholdMB", memInfo.threshold / 1_048_576)
                            addProperty("runtimeMaxMB", Runtime.getRuntime().maxMemory() / 1_048_576)
                        },
                    )

                    // Storage
                    add(
                        "disk",
                        JsonObject().apply {
                            addProperty("freeMB", diskFreeMB)
                            addProperty("totalMB", diskTotalMB)
                        },
                    )

                    // CPU
                    addProperty("processorCount", Runtime.getRuntime().availableProcessors())
                    addProperty("supportedAbis", Build.SUPPORTED_ABIS.joinToString(","))

                    // Locale & timezone
                    add(
                        "locale",
                        JsonObject().apply {
                            addProperty("language", locale.language)
                            addProperty("country", locale.country)
                            addProperty("variant", locale.variant)
                            addProperty("displayName", locale.displayName)
                        },
                    )
                    add(
                        "timeZone",
                        JsonObject().apply {
                            val tz = java.util.TimeZone.getDefault()
                            addProperty("id", tz.id)
                            addProperty("displayName", tz.displayName)
                            addProperty("offsetSeconds", tz.rawOffset / 1000)
                            addProperty("usesDST", tz.useDaylightTime())
                        },
                    )

                    // Declared permissions
                    add(
                        "declaredPermissions",
                        com.google.gson.JsonArray().also { arr ->
                            declaredPermissions.forEach { arr.add(it) }
                        },
                    )
                }
            },
        ),
    )

    // -- batch --

    router.register(
        MCPToolDefinition(
            name = "batch",
            description =
                "Execute multiple tool calls in a single request. Actions run sequentially. " +
                    "Each action can have an optional delay_ms (milliseconds to wait BEFORE executing that action) " +
                    "to account for animations, screen transitions, or loading. Returns results for every action.",
            inputSchema =
                jsonSchema(
                    "actions" to
                        JsonObject().apply {
                            addProperty("type", "array")
                            addProperty("description", "Array of actions. Each: {\"tool\": \"tool_name\", \"arguments\": {...}, \"delay_ms\": 500}")
                            add(
                                "items",
                                JsonObject().apply {
                                    addProperty("type", "object")
                                    add(
                                        "properties",
                                        JsonObject().apply {
                                            add("tool", jsonProp("string", "Tool name"))
                                            add(
                                                "arguments",
                                                JsonObject().apply {
                                                    addProperty("type", "object")
                                                    addProperty("description", "Tool arguments")
                                                },
                                            )
                                            add(
                                                "delay_ms",
                                                jsonProp("integer", "Milliseconds to wait before this action (for animations/transitions)"),
                                            )
                                        },
                                    )
                                    add("required", JsonArray().apply { add("tool") })
                                },
                            )
                        },
                    "stop_on_error" to jsonProp("boolean", "Stop executing remaining actions if one fails (default: false)"),
                    required = listOf("actions"),
                ),
            handler = { params ->
                val actionsArray =
                    params?.getAsJsonArray("actions")
                        ?: return@MCPToolDefinition errorResult("actions array required")

                val stopOnError =
                    params.get("stop_on_error")?.let {
                        if (it.isJsonPrimitive) it.asBoolean else false
                    } ?: false

                val results = JsonArray()

                for (index in 0 until actionsArray.size()) {
                    val action = actionsArray[index]
                    if (!action.isJsonObject) {
                        results.add(
                            JsonObject().apply {
                                addProperty("index", index)
                                addProperty("error", "Invalid action format")
                            },
                        )
                        if (stopOnError) break
                        continue
                    }

                    val actionObj = action.asJsonObject
                    val toolName = actionObj.get("tool")?.asStringOrNull()
                    if (toolName == null) {
                        results.add(
                            JsonObject().apply {
                                addProperty("index", index)
                                addProperty("error", "Invalid action format")
                            },
                        )
                        if (stopOnError) break
                        continue
                    }

                    // Delay before this action
                    val delayMs = actionObj.get("delay_ms")?.asIntOrNull() ?: 0
                    if (delayMs > 0) {
                        Thread.sleep(delayMs.toLong())
                    }

                    val tool = router.tool(toolName)
                    if (tool == null) {
                        results.add(
                            JsonObject().apply {
                                addProperty("index", index)
                                addProperty("tool", toolName)
                                addProperty("error", "Tool not found")
                            },
                        )
                        if (stopOnError) break
                        continue
                    }

                    try {
                        val arguments = actionObj.getAsJsonObject("arguments")
                        val result = tool.handler(arguments)
                        val resultJson = MCPGson.gson.toJson(result)
                        results.add(
                            JsonObject().apply {
                                addProperty("index", index)
                                addProperty("tool", toolName)
                                addProperty("result", resultJson)
                            },
                        )
                    } catch (e: Exception) {
                        results.add(
                            JsonObject().apply {
                                addProperty("index", index)
                                addProperty("tool", toolName)
                                addProperty("error", e.message ?: "Unknown error")
                            },
                        )
                        if (stopOnError) break
                    }
                }

                JsonObject().apply {
                    add("results", results)
                    addProperty("count", results.size())
                }
            },
        ),
    )
}

// -- Helper functions --

private fun errorResult(message: String): JsonElement = JsonObject().apply { addProperty("error", message) }

private fun jsonProp(
    type: String,
    description: String? = null,
): JsonObject =
    JsonObject().apply {
        addProperty("type", type)
        if (description != null) addProperty("description", description)
    }

private fun jsonSchema(
    vararg props: Pair<String, JsonObject>,
    required: List<String>? = null,
): JsonObject =
    JsonObject().apply {
        addProperty("type", "object")
        add(
            "properties",
            JsonObject().apply {
                for ((name, schema) in props) {
                    add(name, schema)
                }
            },
        )
        if (required != null) {
            add("required", JsonArray().apply { required.forEach { add(it) } })
        }
    }

private fun jsonSchema(): JsonObject =
    JsonObject().apply {
        addProperty("type", "object")
        add("properties", JsonObject())
    }

internal fun JsonElement.asStringOrNull(): String? = if (isJsonPrimitive && asJsonPrimitive.isString) asString else null

internal fun JsonElement.asIntOrNull(): Int? =
    try {
        if (isJsonPrimitive) asInt else null
    } catch (_: Exception) {
        null
    }

private fun List<String>.toJsonArray(): JsonArray {
    val arr = JsonArray()
    for (s in this) arr.add(s)
    return arr
}

private fun Map<String, Any?>.toJsonObject(): JsonElement {
    val obj = JsonObject()
    for ((key, value) in this) {
        when (value) {
            null -> {
                obj.add(key, com.google.gson.JsonNull.INSTANCE)
            }

            is String -> {
                obj.addProperty(key, value)
            }

            is Number -> {
                obj.addProperty(key, value)
            }

            is Boolean -> {
                obj.addProperty(key, value)
            }

            is List<*> -> {
                obj.add(key, (value as List<Any?>).toJsonElement())
            }

            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                obj.add(key, (value as Map<String, Any?>).toJsonObject())
            }

            else -> {
                obj.addProperty(key, value.toString())
            }
        }
    }
    return obj
}

private fun List<Any?>.toJsonElement(): JsonElement {
    val arr = JsonArray()
    for (item in this) {
        when (item) {
            null -> {
                arr.add(com.google.gson.JsonNull.INSTANCE)
            }

            is String -> {
                arr.add(item)
            }

            is Number -> {
                arr.add(item)
            }

            is Boolean -> {
                arr.add(item)
            }

            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                arr.add((item as Map<String, Any?>).toJsonObject())
            }

            is List<*> -> {
                arr.add((item as List<Any?>).toJsonElement())
            }

            else -> {
                arr.add(item.toString())
            }
        }
    }
    return arr
}
