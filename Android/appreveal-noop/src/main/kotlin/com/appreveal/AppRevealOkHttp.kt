package com.appreveal

import com.appreveal.network.NetworkCaptureConfig
import okhttp3.Interceptor
import okhttp3.OkHttpClient

object AppRevealOkHttp {
    @JvmStatic
    @JvmOverloads
    fun install(
        builder: OkHttpClient.Builder,
        config: NetworkCaptureConfig = NetworkCaptureConfig(),
    ): OkHttpClient.Builder = builder

    @JvmStatic
    @JvmOverloads
    fun interceptor(config: NetworkCaptureConfig = NetworkCaptureConfig()): Interceptor = Interceptor { chain -> chain.proceed(chain.request()) }
}
