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
    private val capturedRequests = LinkedHashMap<String, CapturedRequest>()
    private var observable: NetworkObservable? = null

    @Synchronized
    fun register(observable: NetworkObservable) {
        this.observable = observable
        observable.addObserver(this)
        observable.recentRequests.forEach(::didCapture)
    }

    @Synchronized
    override fun didCapture(request: CapturedRequest) {
        addOrUpdate(request.withRedactedHeaders())
    }

    @Synchronized
    fun addCall(request: CapturedRequest) {
        addOrUpdate(request.withRedactedHeaders())
    }

    @Synchronized
    fun updateCall(
        id: String,
        transform: (CapturedRequest) -> CapturedRequest,
    ) {
        val existing = capturedRequests[id] ?: return
        addOrUpdate(transform(existing).withRedactedHeaders())
    }

    @Synchronized
    fun recentCalls(limit: Int = 50): List<CapturedRequest> {
        val size = capturedRequests.size
        val fromIndex = maxOf(0, size - limit)
        return capturedRequests.values.toList().subList(fromIndex, size).toList()
    }

    @Synchronized
    fun callDetail(id: String): CapturedRequest? = capturedRequests[id]

    @Synchronized
    fun clear() {
        capturedRequests.clear()
    }

    private fun addOrUpdate(request: CapturedRequest) {
        capturedRequests[request.id] = request
        while (capturedRequests.size > MAX_BUFFER_SIZE) {
            val oldest = capturedRequests.keys.firstOrNull() ?: return
            capturedRequests.remove(oldest)
        }
    }
}
