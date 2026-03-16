package com.appreveal.example

import android.app.Application
import com.appreveal.AppReveal
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.services.ExampleFeatureFlags
import com.appreveal.example.services.ExampleNetworkClient
import com.appreveal.example.services.ExampleStateContainer

class ExampleApp : Application() {

    override fun onCreate() {
        super.onCreate()

        if (BuildConfig.DEBUG) {
            AppReveal.start(this)
            AppReveal.registerStateProvider(ExampleStateContainer)
            AppReveal.registerNavigationProvider(ExampleRouter)
            AppReveal.registerFeatureFlagProvider(ExampleFeatureFlags)
            AppReveal.registerNetworkObservable(ExampleNetworkClient)
        }
    }
}
