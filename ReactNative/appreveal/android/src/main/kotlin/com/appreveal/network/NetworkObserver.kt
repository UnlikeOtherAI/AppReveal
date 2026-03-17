package com.appreveal.network

/**
 * Internal service that collects network traffic in a ring buffer.
 * In React Native, calls are fed directly from JS via AppRevealModule.captureNetworkCall().
 * No NetworkObservable interface — JS is the sole source of network events.
 */
internal object NetworkObserverService {

    private const val MAX_BUFFER_SIZE = 200
    private val capturedRequests = mutableListOf<CapturedRequest>()

    @Synchronized
    fun addCall(call: CapturedRequest) {
        capturedRequests.add(call.withRedactedHeaders())
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
