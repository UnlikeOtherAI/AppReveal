package com.appreveal

import android.app.Application
import com.appreveal.network.NetworkObservable
import com.appreveal.state.FeatureFlagProviding
import com.appreveal.state.NavigationProviding
import com.appreveal.state.StateProviding

object AppReveal {
    @JvmStatic
    val sessionToken: String? get() = null

    @JvmStatic
    val url: String? get() = null

    @JvmStatic
    val sessionUrl: String? get() = null

    @JvmStatic
    fun start(
        application: Application,
        port: Int = 0,
    ) {}

    @JvmStatic
    fun stop() {}

    @JvmStatic
    fun registerStateProvider(provider: StateProviding) {}

    @JvmStatic
    fun registerNavigationProvider(provider: NavigationProviding) {}

    @JvmStatic
    fun registerFeatureFlagProvider(provider: FeatureFlagProviding) {}

    @JvmStatic
    fun registerNetworkObservable(observable: NetworkObservable) {}
}
