package com.appreveal.example.services

import android.os.Handler
import android.os.Looper
import com.appreveal.AppRevealOkHttp
import com.appreveal.example.models.ExampleOrder
import com.appreveal.example.models.ExampleProduct
import com.appreveal.network.CapturedRequest
import com.appreveal.network.NetworkCaptureConfig
import com.appreveal.network.NetworkObservable
import com.appreveal.network.NetworkTrafficObserver
import okhttp3.Callback
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import java.io.IOException

object ExampleNetworkClient : NetworkObservable {

    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableListOf<NetworkTrafficObserver>()
    private val jsonMediaType = "application/json".toMediaType()
    private val client =
        AppRevealOkHttp
            .install(
                OkHttpClient.Builder(),
                NetworkCaptureConfig(maxBodyBytes = 64L * 1024L),
            ).addInterceptor { chain ->
                val request = chain.request()
                Response
                    .Builder()
                    .request(request)
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("OK")
                    .header("Content-Type", "application/json")
                    .body(fakeResponseBody(request.url.encodedPath).toResponseBody(jsonMediaType))
                    .build()
            }.build()

    override val recentRequests: List<CapturedRequest> = emptyList()

    override fun addObserver(observer: NetworkTrafficObserver) {
        observers.add(observer)
    }

    fun login(email: String, password: String, callback: (Result<Unit>) -> Unit) {
        simulateRequest("POST", "/api/auth/login", """{"email":"$email","password":"$password"}""") {
            if (email.contains("@") && password.isNotEmpty()) {
                callback(Result.success(Unit))
            } else {
                callback(Result.failure(Exception("Invalid email or password")))
            }
        }
    }

    fun fetchOrders(callback: (Result<List<ExampleOrder>>) -> Unit) {
        simulateRequest("GET", "/api/orders") {
            callback(Result.success(ExampleOrder.samples))
        }
    }

    fun fetchOrderDetail(id: String, callback: (Result<ExampleOrder>) -> Unit) {
        simulateRequest("GET", "/api/orders/$id") {
            val order = ExampleOrder.samples.firstOrNull { it.id == id }
                ?: ExampleOrder.samples[0]
            callback(Result.success(order))
        }
    }

    fun fetchProducts(callback: (Result<List<ExampleProduct>>) -> Unit) {
        simulateRequest("GET", "/api/products") {
            callback(Result.success(ExampleProduct.samples))
        }
    }

    fun fetchProfile(callback: (Result<Map<String, String>>) -> Unit) {
        simulateRequest("GET", "/api/profile") {
            callback(Result.success(mapOf("name" to "Test User", "email" to "test@example.com")))
        }
    }

    private fun simulateRequest(
        method: String,
        path: String,
        requestJson: String? = null,
        delayMs: Long = 300,
        work: () -> Unit
    ) {
        val url = "https://api.example.com$path"
        handler.postDelayed({
            val body = requestJson?.toRequestBody(jsonMediaType)
            val request =
                Request
                    .Builder()
                    .url(url)
                    .header("Accept", "application/json")
                    .header("Authorization", "Bearer token123")
                    .method(method, body)
                    .build()
            client.newCall(request).enqueue(
                object : Callback {
                    override fun onFailure(
                        call: Call,
                        e: IOException,
                    ) {
                        handler.post(work)
                    }

                    override fun onResponse(
                        call: Call,
                        response: Response,
                    ) {
                        response.use { it.body?.string() }
                        handler.post(work)
                    }
                },
            )
        }, delayMs)
    }

    private fun fakeResponseBody(path: String): String =
        when {
            path.endsWith("/auth/login") -> """{"ok":true,"token":"debug-token"}"""
            path.endsWith("/orders") -> """{"items":${ExampleOrder.samples.size}}"""
            path.contains("/orders/") -> """{"id":"${path.substringAfterLast("/")}"}"""
            path.endsWith("/products") -> """{"items":${ExampleProduct.samples.size}}"""
            path.endsWith("/profile") -> """{"name":"Test User","email":"test@example.com"}"""
            else -> """{"ok":true}"""
        }
}
