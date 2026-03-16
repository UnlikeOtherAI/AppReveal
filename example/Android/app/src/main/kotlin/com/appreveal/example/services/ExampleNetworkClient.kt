package com.appreveal.example.services

import android.os.Handler
import android.os.Looper
import com.appreveal.example.models.ExampleOrder
import com.appreveal.example.models.ExampleProduct
import com.appreveal.network.CapturedRequest
import com.appreveal.network.NetworkObservable
import com.appreveal.network.NetworkTrafficObserver

object ExampleNetworkClient : NetworkObservable {

    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableListOf<NetworkTrafficObserver>()

    override val recentRequests: List<CapturedRequest> = emptyList()

    override fun addObserver(observer: NetworkTrafficObserver) {
        observers.add(observer)
    }

    fun login(email: String, password: String, callback: (Result<Unit>) -> Unit) {
        simulateRequest("POST", "/api/auth/login") {
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
        delayMs: Long = 300,
        work: () -> Unit
    ) {
        val url = "https://api.example.com$path"
        val startTime = System.currentTimeMillis()

        handler.postDelayed({
            val captured = CapturedRequest(
                method = method,
                url = url,
                statusCode = 200,
                startTime = startTime,
                endTime = System.currentTimeMillis(),
                duration = delayMs.toDouble() / 1000.0,
                requestHeaders = mapOf(
                    "Content-Type" to "application/json",
                    "Authorization" to "Bearer token123"
                ),
                responseHeaders = mapOf("Content-Type" to "application/json"),
                requestBodySize = if (method == "POST") 128 else null,
                responseBodySize = 2048,
                redirectCount = 0
            )
            observers.forEach { it.didCapture(captured) }
            work()
        }, delayMs)
    }
}
