package com.appreveal

import android.util.Log
import com.appreveal.diagnostics.DiagnosticsBridge
import com.appreveal.discovery.NsdAdvertiser
import com.appreveal.mcpserver.MCPServer
import com.appreveal.mcpserver.registerBuiltInTools
import com.appreveal.network.CapturedRequest
import com.appreveal.network.NetworkObserverService
import com.appreveal.screen.ScreenResolver
import com.appreveal.state.StateBridge
import com.appreveal.webview.registerWebViewTools
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.module.annotations.ReactModule

@ReactModule(name = AppRevealModule.NAME)
class AppRevealModule(private val reactContext: ReactApplicationContext)
    : ReactContextBaseJavaModule(reactContext) {

    companion object {
        const val NAME = "AppReveal"
        private const val TAG = "AppReveal"
    }

    private var server: MCPServer? = null
    private var advertiser: NsdAdvertiser? = null

    override fun getName() = NAME

    @ReactMethod
    fun start(port: Double) {
        val portInt = port.toInt()

        val application = reactContext.applicationContext as? android.app.Application
        if (application != null) {
            ScreenResolver.init(reactContext)
        }

        registerBuiltInTools()
        registerWebViewTools()

        val srv = MCPServer(portInt)
        srv.start()
        server = srv
        Log.i(TAG, "MCP server listening on port ${srv.actualPort}")

        advertiser = NsdAdvertiser(reactContext.applicationContext, srv.actualPort)
        advertiser?.register()
    }

    @ReactMethod
    fun stop() {
        advertiser?.unregister()
        server?.stop()
        server = null
        advertiser = null
    }

    @ReactMethod
    fun setScreen(key: String, title: String, confidence: Double) {
        ScreenResolver.setJsScreen(key, title)
    }

    @ReactMethod
    fun setNavigationStack(routes: ReadableArray, current: String, modals: ReadableArray) {
        val routesList = mutableListOf<String>()
        for (i in 0 until routes.size()) {
            routesList.add(routes.getString(i) ?: "")
        }
        val modalsList = mutableListOf<String>()
        for (i in 0 until modals.size()) {
            modalsList.add(modals.getString(i) ?: "")
        }
        StateBridge.currentRoute = current
        StateBridge.navigationStack = routesList
        StateBridge.presentedModals = modalsList
    }

    @ReactMethod
    fun setFeatureFlags(flags: ReadableMap) {
        val map = mutableMapOf<String, Any>()
        val iterator = flags.keySetIterator()
        while (iterator.hasNextKey()) {
            val key = iterator.nextKey()
            when (flags.getType(key)) {
                com.facebook.react.bridge.ReadableType.Boolean -> map[key] = flags.getBoolean(key)
                com.facebook.react.bridge.ReadableType.Number -> map[key] = flags.getDouble(key)
                com.facebook.react.bridge.ReadableType.String -> map[key] = flags.getString(key) ?: ""
                else -> {} // Skip complex types
            }
        }
        StateBridge.featureFlags = map
    }

    @ReactMethod
    fun captureNetworkCall(call: ReadableMap) {
        val id = call.getString("id") ?: java.util.UUID.randomUUID().toString()
        val method = call.getString("method") ?: "GET"
        val url = call.getString("url") ?: ""
        val statusCode = if (call.hasKey("statusCode") && !call.isNull("statusCode")) {
            call.getInt("statusCode")
        } else null
        val duration = if (call.hasKey("duration") && !call.isNull("duration")) {
            call.getDouble("duration")
        } else null
        val error = if (call.hasKey("error") && !call.isNull("error")) {
            call.getString("error")
        } else null

        val request = CapturedRequest(
            id = id,
            method = method,
            url = url,
            statusCode = statusCode,
            duration = duration,
            error = error
        )
        NetworkObserverService.addCall(request)
    }

    @ReactMethod
    fun captureError(domain: String, message: String, stackTrace: String) {
        DiagnosticsBridge.captureError(domain, message, stackTrace.ifEmpty { null })
    }
}
