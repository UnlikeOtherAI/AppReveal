package com.appreveal.screenshot

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.PixelCopy
import android.view.View
import com.appreveal.elements.ElementInventory
import com.appreveal.screen.ScreenResolver
import com.appreveal.shared.MainThreadExecutor
import java.io.ByteArrayOutputStream
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * Captures screenshots using PixelCopy (API 26+) for full screen,
 * and drawToBitmap for individual elements.
 */
internal object ScreenshotCapture {
    data class CaptureResult(
        val imageData: String, // base64-encoded
        val width: Int,
        val height: Int,
        val scale: Float,
        val format: String,
    )

    fun captureScreen(format: String = "png"): CaptureResult? {
        val activity = ScreenResolver.currentActivity ?: return null
        val window = activity.window ?: return null
        val decorView = window.decorView

        val width = decorView.width
        val height = decorView.height
        if (width <= 0 || height <= 0) return null

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val future = CompletableFuture<Int>()
        val handler = Handler(Looper.getMainLooper())

        PixelCopy.request(window, bitmap, { result ->
            future.complete(result)
        }, handler)

        val result = future.get(5, TimeUnit.SECONDS)
        if (result != PixelCopy.SUCCESS) return null

        val base64 = encodeBitmap(bitmap, format)
        val density = activity.resources.displayMetrics.density

        return CaptureResult(
            imageData = base64,
            width = width,
            height = height,
            scale = density,
            format = format,
        )
    }

    fun captureElement(
        elementId: String,
        format: String = "png",
    ): CaptureResult? {
        return MainThreadExecutor.runBlocking {
            val view = ElementInventory.findElement(elementId) ?: return@runBlocking null

            val bitmap =
                try {
                    view.drawToBitmap()
                } catch (_: Exception) {
                    return@runBlocking null
                }

            val base64 = encodeBitmap(bitmap, format)
            val density = view.resources.displayMetrics.density

            CaptureResult(
                imageData = base64,
                width = bitmap.width,
                height = bitmap.height,
                scale = density,
                format = format,
            )
        }
    }

    private fun encodeBitmap(
        bitmap: Bitmap,
        format: String,
    ): String {
        val stream = ByteArrayOutputStream()
        val compressFormat =
            if (format == "jpeg") {
                Bitmap.CompressFormat.JPEG
            } else {
                Bitmap.CompressFormat.PNG
            }
        val quality = if (format == "jpeg") 85 else 100
        bitmap.compress(compressFormat, quality, stream)
        val bytes = stream.toByteArray()
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }
}
