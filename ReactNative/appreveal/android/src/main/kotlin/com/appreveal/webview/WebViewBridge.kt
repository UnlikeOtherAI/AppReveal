package com.appreveal.webview

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import com.appreveal.screen.ScreenResolver
import com.appreveal.shared.MainThreadExecutor
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * Discovers WebView instances and evaluates JavaScript in them.
 * Uses reactContext.currentActivity for activity access in React Native.
 */
internal object WebViewBridge {

    /**
     * Find all WebView instances in the current activity's view tree.
     */
    fun findWebViews(): List<Pair<String, WebView>> {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView
                ?: return@runBlocking emptyList()
            val results = mutableListOf<Pair<String, WebView>>()
            var counter = 0
            collectWebViews(decorView, results, counter)
            results
        }
    }

    private fun collectWebViews(view: View, results: MutableList<Pair<String, WebView>>, counter: Int) {
        var idx = counter
        if (view is WebView) {
            val id = view.contentDescription?.toString()
                ?: (if (view.id != View.NO_ID) {
                    try { view.resources.getResourceEntryName(view.id) } catch (_: Exception) { null }
                } else null)
                ?: "webview_$idx"
            results.add(Pair(id, view))
            idx++
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child.visibility != View.GONE) {
                    collectWebViews(child, results, idx)
                }
            }
        }
    }

    /**
     * Resolve a WebView by ID, or return the first one found.
     */
    fun resolveWebView(id: String?): WebView? {
        val webViews = findWebViews()
        if (id != null) {
            return webViews.firstOrNull { it.first == id }?.second
        }
        return webViews.firstOrNull()?.second
    }

    /**
     * Get metadata about all discovered WebViews.
     */
    fun webViewInfo(): List<Map<String, Any>> {
        return MainThreadExecutor.runBlocking {
            val webViews = findWebViews()
            webViews.map { (id, webView) ->
                val location = IntArray(2)
                webView.getLocationOnScreen(location)
                mapOf(
                    "id" to id,
                    "url" to (webView.url ?: ""),
                    "title" to (webView.title ?: ""),
                    "loading" to (webView.progress < 100),
                    "canGoBack" to webView.canGoBack(),
                    "canGoForward" to webView.canGoForward(),
                    "frame" to "${location[0]},${location[1]},${webView.width},${webView.height}"
                )
            }
        }
    }

    /**
     * Evaluate JavaScript in a WebView.
     * Handles Android-specific issue where evaluateJavascript returns JSON-encoded strings
     * (strips surrounding quotes if the result is a JSON string).
     */
    fun evaluate(js: String, webViewId: String?): String {
        val future = CompletableFuture<String>()

        MainThreadExecutor.runBlocking {
            val webView = resolveWebView(webViewId)
                ?: throw WebViewError.NotFound(webViewId ?: "default")

            webView.evaluateJavascript(js) { rawResult ->
                if (rawResult == null || rawResult == "null") {
                    future.complete("null")
                } else if (rawResult.startsWith("\"") && rawResult.endsWith("\"")) {
                    // Android evaluateJavascript JSON-encodes string results.
                    // Decode the JSON string to get the actual value.
                    val decoded = rawResult
                        .substring(1, rawResult.length - 1)
                        .replace("\\\"", "\"")
                        .replace("\\\\", "\\")
                        .replace("\\n", "\n")
                        .replace("\\r", "\r")
                        .replace("\\t", "\t")
                    future.complete(decoded)
                } else {
                    future.complete(rawResult)
                }
            }
        }

        return future.get(10, TimeUnit.SECONDS)
    }
}

/**
 * WebView errors.
 */
sealed class WebViewError(message: String) : Exception(message) {
    class NotFound(id: String) : WebViewError("WebView not found: $id")
    class EvaluationFailed(msg: String) : WebViewError("JS evaluation failed: $msg")
}
