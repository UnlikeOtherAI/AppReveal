package com.appreveal.shared

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * Utility to run a block on the main thread and await the result synchronously.
 * Uses Handler(Looper.getMainLooper()) + CompletableFuture with 5-second timeout.
 * If already on the main thread, runs directly.
 */
internal object MainThreadExecutor {
    private val handler = Handler(Looper.getMainLooper())

    /**
     * Run [block] on the main thread and return the result, blocking the caller.
     * If already on the main thread, executes immediately.
     */
    fun <T> runBlocking(block: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return block()
        }

        val future = CompletableFuture<T>()
        handler.post {
            try {
                future.complete(block())
            } catch (e: Throwable) {
                future.completeExceptionally(e)
            }
        }
        return future.get(5, TimeUnit.SECONDS)
    }
}
