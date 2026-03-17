package com.appreveal.webview

import android.net.Uri
import android.webkit.WebView
import com.appreveal.mcpserver.MCPRouter
import com.appreveal.mcpserver.MCPToolDefinition
import com.appreveal.mcpserver.asIntOrNull
import com.appreveal.mcpserver.asStringOrNull
import com.appreveal.shared.MainThreadExecutor
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject

/**
 * Registers all 21 WebView MCP tools with the router,
 * matching the iOS WebViewTools.swift exactly.
 */
internal fun registerWebViewTools() {
    val router = MCPRouter

    // -- get_webviews --

    router.register(MCPToolDefinition(
        name = "get_webviews",
        description = "List all WebView instances on the current screen with URL, title, loading state, and frame",
        inputSchema = emptySchema(),
        handler = { _ ->
            val info = WebViewBridge.webViewInfo()
            val arr = JsonArray()
            for (wv in info) {
                arr.add(JsonObject().apply {
                    addProperty("id", wv["id"] as String)
                    addProperty("url", wv["url"] as String)
                    addProperty("title", wv["title"] as String)
                    addProperty("loading", wv["loading"] as Boolean)
                    addProperty("canGoBack", wv["canGoBack"] as Boolean)
                    addProperty("canGoForward", wv["canGoForward"] as Boolean)
                    addProperty("frame", wv["frame"] as String)
                })
            }
            JsonObject().apply {
                add("webviews", arr)
                addProperty("count", arr.size())
            }
        }
    ))

    // -- get_dom_tree --

    router.register(MCPToolDefinition(
        name = "get_dom_tree",
        description = "Get the DOM tree of a web view. Returns full or partial DOM structure as JSON.",
        inputSchema = webViewSchema(
            "root" to prop("string", "CSS selector for subtree root (default: body)"),
            "max_depth" to prop("integer", "Max tree depth (default: 30)"),
            "visible_only" to prop("boolean", "Only visible elements (default: false)")
        ),
        handler = { params ->
            val js = DOMSerializer.dumpTreeJS(
                root = params?.get("root")?.asStringOrNull(),
                maxDepth = params?.get("max_depth")?.asIntOrNull() ?: 30,
                visibleOnly = params?.get("visible_only")?.let {
                    if (it.isJsonPrimitive) it.asBoolean else false
                } ?: false
            )
            evalAndWrap(js, params?.get("webview_id")?.asStringOrNull(), "dom")
        }
    ))

    // -- get_dom_interactive --

    router.register(MCPToolDefinition(
        name = "get_dom_interactive",
        description = "Get all interactive DOM elements (inputs, buttons, links, selects) with their attributes, values, and selectors",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.interactiveJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- query_dom --

    router.register(MCPToolDefinition(
        name = "query_dom",
        description = "Query the DOM with a CSS selector. Returns matching elements with tag, text, attributes, rect.",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector"),
            "limit" to prop("integer", "Max results (default: 50)"),
            required = listOf("selector")
        ),
        handler = { params ->
            val selector = params?.get("selector")?.asString
                ?: return@MCPToolDefinition webViewError("selector required")
            val js = DOMSerializer.queryJS(selector, params.get("limit")?.asIntOrNull() ?: 50)
            evalAndWrap(js, params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- find_dom_text --

    router.register(MCPToolDefinition(
        name = "find_dom_text",
        description = "Find DOM elements containing specific text",
        inputSchema = webViewSchema(
            "text" to prop("string", "Text to search for"),
            "tag" to prop("string", "Optional tag filter (e.g. 'button', 'a')"),
            required = listOf("text")
        ),
        handler = { params ->
            val text = params?.get("text")?.asString
                ?: return@MCPToolDefinition webViewError("text required")
            val js = DOMSerializer.findTextJS(text, params.get("tag")?.asStringOrNull())
            evalAndWrap(js, params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_click --

    router.register(MCPToolDefinition(
        name = "web_click",
        description = "Click a DOM element by CSS selector",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector"),
            required = listOf("selector")
        ),
        handler = { params ->
            val selector = params?.get("selector")?.asString
                ?: return@MCPToolDefinition webViewError("selector required")
            evalAndWrap(DOMSerializer.clickJS(selector), params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_type --

    router.register(MCPToolDefinition(
        name = "web_type",
        description = "Type text into a DOM input or textarea by CSS selector",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector"),
            "text" to prop("string", "Text to type"),
            "clear" to prop("boolean", "Clear field first (default: false)"),
            required = listOf("selector", "text")
        ),
        handler = { params ->
            val selector = params?.get("selector")?.asString
            val text = params?.get("text")?.asString
            if (selector == null || text == null) {
                return@MCPToolDefinition webViewError("selector and text required")
            }
            val clear = params.get("clear")?.let {
                if (it.isJsonPrimitive) it.asBoolean else false
            } ?: false
            evalAndWrap(DOMSerializer.typeJS(selector, text, clear), params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_select --

    router.register(MCPToolDefinition(
        name = "web_select",
        description = "Select an option in a dropdown by CSS selector",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector for the select element"),
            "value" to prop("string", "Option value to select"),
            required = listOf("selector", "value")
        ),
        handler = { params ->
            val selector = params?.get("selector")?.asString
            val value = params?.get("value")?.asString
            if (selector == null || value == null) {
                return@MCPToolDefinition webViewError("selector and value required")
            }
            evalAndWrap(DOMSerializer.selectJS(selector, value), params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_toggle --

    router.register(MCPToolDefinition(
        name = "web_toggle",
        description = "Check or uncheck a checkbox/radio by CSS selector",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector"),
            "checked" to prop("boolean", "Desired checked state"),
            required = listOf("selector", "checked")
        ),
        handler = { params ->
            val selector = params?.get("selector")?.asString
            val checked = params?.get("checked")?.let {
                if (it.isJsonPrimitive) it.asBoolean else null
            }
            if (selector == null || checked == null) {
                return@MCPToolDefinition webViewError("selector and checked required")
            }
            evalAndWrap(DOMSerializer.toggleJS(selector, checked), params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_scroll_to --

    router.register(MCPToolDefinition(
        name = "web_scroll_to",
        description = "Scroll a web view until a DOM element is visible",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector"),
            required = listOf("selector")
        ),
        handler = { params ->
            val selector = params?.get("selector")?.asString
                ?: return@MCPToolDefinition webViewError("selector required")
            evalAndWrap(DOMSerializer.scrollToJS(selector), params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_evaluate --

    router.register(MCPToolDefinition(
        name = "web_evaluate",
        description = "Run arbitrary JavaScript in a web view and return the result",
        inputSchema = webViewSchema(
            "javascript" to prop("string", "JavaScript to evaluate"),
            required = listOf("javascript")
        ),
        handler = { params ->
            val js = params?.get("javascript")?.asString
                ?: return@MCPToolDefinition webViewError("javascript required")
            evalAndWrap(js, params.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- web_navigate --

    router.register(MCPToolDefinition(
        name = "web_navigate",
        description = "Navigate a web view to a URL",
        inputSchema = webViewSchema(
            "url" to prop("string", "URL to navigate to"),
            required = listOf("url")
        ),
        handler = { params ->
            val urlStr = params?.get("url")?.asString
                ?: return@MCPToolDefinition webViewError("Invalid URL")
            val webViewId = params.get("webview_id")?.asStringOrNull()
            try {
                MainThreadExecutor.runBlocking {
                    val webView = WebViewBridge.resolveWebView(webViewId)
                        ?: throw WebViewError.NotFound(webViewId ?: "default")
                    webView.loadUrl(urlStr)
                }
                JsonObject().apply {
                    addProperty("success", true)
                    addProperty("url", urlStr)
                }
            } catch (e: Exception) {
                webViewError(e.message ?: "Navigation failed")
            }
        }
    ))

    // -- web_back --

    router.register(MCPToolDefinition(
        name = "web_back",
        description = "Go back in web view history",
        inputSchema = webViewSchema(),
        handler = { params ->
            val webViewId = params?.get("webview_id")?.asStringOrNull()
            try {
                MainThreadExecutor.runBlocking {
                    val webView = WebViewBridge.resolveWebView(webViewId)
                        ?: throw WebViewError.NotFound(webViewId ?: "default")
                    if (!webView.canGoBack()) throw Exception("Cannot go back")
                    webView.goBack()
                }
                JsonObject().apply { addProperty("success", true) }
            } catch (e: Exception) {
                webViewError(e.message ?: "Cannot go back")
            }
        }
    ))

    // -- web_forward --

    router.register(MCPToolDefinition(
        name = "web_forward",
        description = "Go forward in web view history",
        inputSchema = webViewSchema(),
        handler = { params ->
            val webViewId = params?.get("webview_id")?.asStringOrNull()
            try {
                MainThreadExecutor.runBlocking {
                    val webView = WebViewBridge.resolveWebView(webViewId)
                        ?: throw WebViewError.NotFound(webViewId ?: "default")
                    if (!webView.canGoForward()) throw Exception("Cannot go forward")
                    webView.goForward()
                }
                JsonObject().apply { addProperty("success", true) }
            } catch (e: Exception) {
                webViewError(e.message ?: "Cannot go forward")
            }
        }
    ))

    // -- get_dom_links --

    router.register(MCPToolDefinition(
        name = "get_dom_links",
        description = "Get all links on the page -- just text and href. Minimal tokens.",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.linksJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- get_dom_text --

    router.register(MCPToolDefinition(
        name = "get_dom_text",
        description = "Get visible text content of the page stripped of all markup. Optionally scope to a CSS selector. Minimal tokens.",
        inputSchema = webViewSchema(
            "selector" to prop("string", "CSS selector to scope text extraction (default: body)")
        ),
        handler = { params ->
            val js = DOMSerializer.textContentJS(params?.get("selector")?.asStringOrNull())
            evalAndWrap(js, params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- get_dom_forms --

    router.register(MCPToolDefinition(
        name = "get_dom_forms",
        description = "Get all forms and their fields with types, names, values, options, and selectors. Includes pages without <form> tags.",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.formsJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- get_dom_headings --

    router.register(MCPToolDefinition(
        name = "get_dom_headings",
        description = "Get all headings (h1-h6) for page structure overview. Minimal tokens.",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.headingsJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- get_dom_images --

    router.register(MCPToolDefinition(
        name = "get_dom_images",
        description = "Get all visible images with src, alt text, and dimensions.",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.imagesJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- get_dom_tables --

    router.register(MCPToolDefinition(
        name = "get_dom_tables",
        description = "Get all tables with headers and row data.",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.tablesJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))

    // -- get_dom_summary --

    router.register(MCPToolDefinition(
        name = "get_dom_summary",
        description = "Get a compact page summary: title, meta, headings (h1-h3), element counts (links, images, inputs, buttons), and form overview. Cheapest way to understand a page.",
        inputSchema = webViewSchema(),
        handler = { params ->
            evalAndWrap(DOMSerializer.summaryJS(), params?.get("webview_id")?.asStringOrNull(), "result")
        }
    ))
}

// -- Helper functions --

private fun evalAndWrap(js: String, webViewId: String?, resultKey: String): JsonElement {
    return try {
        val result = WebViewBridge.evaluate(js, webViewId)
        JsonObject().apply { addProperty(resultKey, result) }
    } catch (e: Exception) {
        webViewError(e.message ?: "Evaluation failed")
    }
}

private fun webViewError(message: String): JsonElement {
    return JsonObject().apply { addProperty("error", message) }
}

private fun prop(type: String, description: String? = null): JsonObject {
    return JsonObject().apply {
        addProperty("type", type)
        if (description != null) addProperty("description", description)
    }
}

private fun emptySchema(): JsonObject {
    return JsonObject().apply {
        addProperty("type", "object")
        add("properties", JsonObject())
    }
}

private fun webViewSchema(vararg props: Pair<String, JsonObject>, required: List<String>? = null): JsonObject {
    return JsonObject().apply {
        addProperty("type", "object")
        add("properties", JsonObject().apply {
            add("webview_id", prop("string", "Web view ID (default: first on screen)"))
            for ((name, schema) in props) {
                add(name, schema)
            }
        })
        if (required != null) {
            add("required", JsonArray().apply { required.forEach { add(it) } })
        }
    }
}
