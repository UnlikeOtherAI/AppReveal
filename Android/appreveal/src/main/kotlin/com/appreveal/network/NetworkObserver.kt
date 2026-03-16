package com.appreveal.network

/**
 * Implement on your network client to expose traffic to AppReveal.
 */
interface NetworkObservable {
    val recentRequests: List<CapturedRequest>
    fun addObserver(observer: NetworkTrafficObserver)
}

/**
 * Receives network traffic events.
 */
interface NetworkTrafficObserver {
    fun didCapture(request: CapturedRequest)
}

/**
 * Internal service that collects network traffic in a ring buffer.
 */
internal object NetworkObserverService : NetworkTrafficObserver {

    private const val MAX_BUFFER_SIZE = 200
    private val capturedRequests = mutableListOf<CapturedRequest>()
    private var observable: NetworkObservable? = null

    @Synchronized
    fun register(observable: NetworkObservable) {
        this.observable = observable
        observable.addObserver(this)
    }

    @Synchronized
    override fun didCapture(request: CapturedRequest) {
        capturedRequests.add(request.withRedactedHeaders())
        if (capturedRequests.size > MAX_BUFFER_SIZE) {
            capturedRequests.removeAt(0)
        }
    }

    @Synchronized
    fun recentCalls(limit: Int = 50): List<CapturedRequest> {
        val size = capturedRequests.size
        val fromIndex = maxOf(0, size - limit)
        return capturedRequests.subList(fromIndex, size).toList()
    }

    @Synchronized
    fun callDetail(id: String): CapturedRequest? {
        return capturedRequests.firstOrNull { it.id == id }
    }

    @Synchronized
    fun clear() {
        capturedRequests.clear()
    }
}
