package com.appreveal

import android.app.Application
import android.util.Log
import com.appreveal.discovery.NsdAdvertiser
import com.appreveal.mcpserver.MCPServer
import com.appreveal.mcpserver.registerBuiltInTools
import com.appreveal.network.NetworkObservable
import com.appreveal.network.NetworkObserverService
import com.appreveal.screen.ScreenResolver
import com.appreveal.state.FeatureFlagProviding
import com.appreveal.state.NavigationProviding
import com.appreveal.state.StateBridge
import com.appreveal.state.StateProviding
import com.appreveal.webview.registerWebViewTools

/**
 * Main entry point for the AppReveal debug framework.
 * Call `AppReveal.start(application)` in your Application.onCreate() within a debug check.
 */
object AppReveal {
    private var server: MCPServer? = null
    private var advertiser: NsdAdvertiser? = null
    internal var application: Application? = null

    @JvmStatic
    val sessionToken: String?
        get() = server?.sessionToken

    @JvmStatic
    val url: String?
        get() = server?.url

    @JvmStatic
    val sessionUrl: String?
        get() = server?.sessionUrl

    @JvmStatic
    fun start(
        application: Application,
        port: Int = 0,
    ) {
        server?.let {
            Log.i("AppReveal", "start ignored; already running at ${it.sessionUrl}")
            return
        }

        this.application = application
        ScreenResolver.init(application)
        registerBuiltInTools()
        registerWebViewTools()
        val srv = MCPServer(port)
        srv.start()
        server = srv
        Log.i("AppReveal", "MCP server listening on port ${srv.actualPort}")
        Log.i("AppReveal", "Session URL: ${srv.sessionUrl}")
        Log.i("AppReveal", "Clients must include Authorization: Bearer <token> or X-AppReveal-Session.")
        advertiser = NsdAdvertiser(application, srv.actualPort)
        advertiser?.register()
    }

    @JvmStatic
    fun stop() {
        advertiser?.unregister()
        server?.stop()
        server = null
        advertiser = null
    }

    @JvmStatic
    fun registerStateProvider(provider: StateProviding) {
        StateBridge.registerStateProvider(provider)
    }

    @JvmStatic
    fun registerNavigationProvider(provider: NavigationProviding) {
        StateBridge.registerNavigationProvider(provider)
    }

    @JvmStatic
    fun registerFeatureFlagProvider(provider: FeatureFlagProviding) {
        StateBridge.registerFeatureFlagProvider(provider)
    }

    @JvmStatic
    fun registerNetworkObservable(observable: NetworkObservable) {
        NetworkObserverService.register(observable)
    }
}
