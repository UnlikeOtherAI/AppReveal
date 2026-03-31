package com.appreveal

import android.app.Application

object AppReveal {

    @JvmStatic
    fun start(
        application: Application,
        port: Int = 0,
    ) {}

    @JvmStatic
    fun stop() {}

    @JvmStatic
    fun registerStateProvider(provider: Any) {}

    @JvmStatic
    fun registerNavigationProvider(provider: Any) {}

    @JvmStatic
    fun registerFeatureFlagProvider(provider: Any) {}

    @JvmStatic
    fun registerNetworkObservable(observable: Any) {}
}
