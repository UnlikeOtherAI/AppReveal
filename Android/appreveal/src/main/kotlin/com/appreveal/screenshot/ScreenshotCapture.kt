package com.appreveal.screenshot

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.PixelCopy
import androidx.core.view.drawToBitmap
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
        /** base64-encoded image data */
        val imageData: String,
        val width: Int,
        val height: Int,
        val scale: Float,
        val format: String,
    )

    fun captureScreen(format: String = "png"): CaptureResult? {
        require(format == "png" || format == "jpeg") { "Unsupported screenshot format: $format" }
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
        if (result != PixelCopy.SUCCESS) {
            bitmap.recycle()
            return null
        }

        val base64 = encodeBitmap(bitmap, format)
        bitmap.recycle()
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
        require(format == "png" || format == "jpeg") { "Unsupported screenshot format: $format" }
        val nativeCapture =
            MainThreadExecutor.runBlocking {
                val view = ElementInventory.findElement(elementId) ?: return@runBlocking null
                if (!ElementInventory.isVisible(view)) return@runBlocking null

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
                ).also { bitmap.recycle() }
            }
        if (nativeCapture != null) return nativeCapture

        // Compose semantics IDs do not map to Views. Crop the composited window
        // using the same screen-space bounds exposed by get_elements.
        val crop =
            MainThreadExecutor.runBlocking {
                val element =
                    ElementInventory.listElements().firstOrNull { it.id == elementId && it.visible }
                        ?: return@runBlocking null
                val decor = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking null
                val location = IntArray(2)
                decor.getLocationOnScreen(location)
                val frame = element.frame
                Rect(
                    (frame.x - location[0]).toInt(), (frame.y - location[1]).toInt(),
                    (frame.x + frame.width - location[0]).toInt(), (frame.y + frame.height - location[1]).toInt(),
                )
            } ?: return null
        val screen = captureScreen(format) ?: return null
        if (!crop.intersect(0, 0, screen.width, screen.height) || crop.isEmpty) return null
        val bytes = Base64.decode(screen.imageData, Base64.NO_WRAP)
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val cropped = Bitmap.createBitmap(bitmap, crop.left, crop.top, crop.width(), crop.height())
        return try {
            CaptureResult(encodeBitmap(cropped, format), crop.width(), crop.height(), screen.scale, format)
        } finally {
            if (cropped !== bitmap) cropped.recycle()
            bitmap.recycle()
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
