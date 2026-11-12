package com.appreveal.webview

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import com.appreveal.screen.ScreenResolver
import com.appreveal.shared.MainThreadExecutor
import com.google.gson.Gson
import com.google.gson.JsonParser
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * Discovers WebView instances and evaluates JavaScript in them.
 */
internal object WebViewBridge {
    /**
     * Find all WebView instances in the current activity's view tree.
     */
    fun findWebViews(): List<Pair<String, WebView>> {
        return MainThreadExecutor.runBlocking {
            val decorView =
                ScreenResolver.currentActivity?.window?.decorView
                    ?: return@runBlocking emptyList()
            val results = mutableListOf<Pair<String, WebView>>()
            collectWebViews(decorView, results)
            results
        }
    }

    private fun collectWebViews(
        view: View,
        results: MutableList<Pair<String, WebView>>,
    ) {
        if (view is WebView) {
            val id =
                view.contentDescription?.toString()
                    ?: (
                        if (view.id != View.NO_ID) {
                            try {
                                view.resources.getResourceEntryName(view.id)
                            } catch (_: Exception) {
                                null
                            }
                        } else {
                            null
                        }
                    )
                    ?: "webview_${results.size}"
            var uniqueId = id
            var suffix = 1
            while (results.any { it.first == uniqueId }) uniqueId = "${id}_${suffix++}"
            results.add(Pair(uniqueId, view))
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child.visibility != View.GONE) {
                    collectWebViews(child, results)
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
    fun webViewInfo(): List<Map<String, Any>> =
        MainThreadExecutor.runBlocking {
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
                    "frame" to "${location[0]},${location[1]},${webView.width},${webView.height}",
                )
            }
        }

    /**
     * Evaluate JavaScript in a WebView.
     * Handles Android-specific issue where evaluateJavascript returns JSON-encoded strings
     * (strips surrounding quotes if the result is a JSON string).
     */
    fun evaluate(
        js: String,
        webViewId: String?,
    ): String {
        val future = CompletableFuture<String>()

        MainThreadExecutor.runBlocking {
            val webView =
                resolveWebView(webViewId)
                    ?: throw WebViewError.NotFound(webViewId ?: "default")

            // evaluateJavascript reports thrown JS errors as null. Catch inside the page so
            // invalid selectors/scripts cannot masquerade as a successful null result.
            val source = Gson().toJson(js)
            val wrapped = "(function(){try{return JSON.stringify({ok:true,value:(0,eval)($source)});}catch(e){return JSON.stringify({ok:false,error:String(e)});}})()"
            webView.evaluateJavascript(wrapped) { rawResult ->
                try {
                    val envelope = JsonParser.parseString(JsonParser.parseString(rawResult).asString).asJsonObject
                    if (!envelope.get("ok").asBoolean) {
                        future.completeExceptionally(WebViewError.EvaluationFailed(envelope.get("error").asString))
                    } else {
                        val value = envelope.get("value")
                        future.complete(
                            if (value == null || value.isJsonNull) {
                                "null"
                            } else if (value.isJsonPrimitive && value.asJsonPrimitive.isString) {
                                value.asString
                            } else {
                                value.toString()
                            },
                        )
                    }
                } catch (error: Exception) {
                    future.completeExceptionally(WebViewError.EvaluationFailed(error.message ?: "Invalid JavaScript result"))
                }
            }
        }

        return future.get(10, TimeUnit.SECONDS)
    }
}

/**
 * WebView errors.
 */
sealed class WebViewError(
    message: String,
) : Exception(message) {
    class NotFound(
        id: String,
    ) : WebViewError("WebView not found: $id")

    class EvaluationFailed(
        msg: String,
    ) : WebViewError("JS evaluation failed: $msg")
}
