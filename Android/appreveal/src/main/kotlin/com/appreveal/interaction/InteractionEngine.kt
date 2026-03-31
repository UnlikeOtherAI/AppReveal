package com.appreveal.interaction

import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import com.appreveal.elements.ElementInventory
import com.appreveal.screen.ScreenResolver
import com.appreveal.shared.MainThreadExecutor
import com.google.android.material.bottomnavigation.BottomNavigationView

/**
 * Executes UI interactions (tap, type, scroll, navigate).
 * All methods use MainThreadExecutor.runBlocking to run on the main thread.
 */
internal object InteractionEngine {
    // MARK: - Tap

    fun tap(elementId: String) {
        MainThreadExecutor.runBlocking {
            val view =
                ElementInventory.findElement(elementId)
                    ?: throw InteractionError.ElementNotFound(elementId)

            if (view.isClickable || view.hasOnClickListeners()) {
                view.performClick()
            } else {
                // Try to find a parent that is clickable
                var parent: View? = view.parent as? View
                while (parent != null) {
                    if (parent.isClickable || parent.hasOnClickListeners()) {
                        parent.performClick()
                        return@runBlocking
                    }
                    parent = parent.parent as? View
                }
                // Fall back to point tap at center
                val location = IntArray(2)
                view.getLocationOnScreen(location)
                val x = location[0] + view.width / 2f
                val y = location[1] + view.height / 2f
                tapPoint(x, y)
            }
        }
    }

    fun tap(
        x: Float,
        y: Float,
    ) {
        MainThreadExecutor.runBlocking {
            tapPoint(x, y)
        }
    }

    private fun tapPoint(
        x: Float,
        y: Float,
    ) {
        val activity = ScreenResolver.currentActivity ?: return
        val decorView = activity.window?.decorView ?: return

        val downTime = SystemClock.uptimeMillis()
        val downEvent = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0)
        val upEvent = MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, x, y, 0)

        decorView.dispatchTouchEvent(downEvent)
        decorView.dispatchTouchEvent(upEvent)

        downEvent.recycle()
        upEvent.recycle()
    }

    // MARK: - Tap by text

    fun tapByText(
        text: String,
        matchMode: String = "exact",
        occurrence: Int = 0,
    ): Map<String, Any> =
        MainThreadExecutor.runBlocking {
            val (view, candidates) = ElementInventory.findElementByText(text, matchMode, occurrence)
            if (view == null) {
                if (candidates.isEmpty()) {
                    mapOf("success" to false, "error" to "No element found with text: $text")
                } else {
                    mapOf(
                        "success" to false,
                        "error" to "Element not found at occurrence $occurrence",
                        "candidates" to candidates,
                    )
                }
            } else {
                if (view.isClickable || view.hasOnClickListeners()) {
                    view.performClick()
                } else {
                    // Fall back to center-point tap
                    val location = IntArray(2)
                    view.getLocationOnScreen(location)
                    val x = location[0] + view.width / 2f
                    val y = location[1] + view.height / 2f
                    tapPoint(x, y)
                }
                mapOf(
                    "success" to true,
                    "tappedText" to text,
                    "matchMode" to matchMode,
                    "candidates" to candidates,
                )
            }
        }

    // MARK: - Text

    fun type(
        text: String,
        elementId: String?,
    ) {
        MainThreadExecutor.runBlocking {
            val target: View? =
                if (elementId != null) {
                    ElementInventory.findElement(elementId)
                        ?: throw InteractionError.ElementNotFound(elementId)
                } else {
                    ScreenResolver.currentActivity?.currentFocus
                }

            when (target) {
                is EditText -> {
                    target.requestFocus()
                    target.append(text)
                }

                else -> {
                    throw InteractionError.NotEditable(elementId ?: "current focus")
                }
            }
        }
    }

    fun clear(elementId: String) {
        MainThreadExecutor.runBlocking {
            val view =
                ElementInventory.findElement(elementId)
                    ?: throw InteractionError.ElementNotFound(elementId)

            when (view) {
                is EditText -> {
                    view.setText("")
                }

                else -> {
                    throw InteractionError.NotEditable(elementId)
                }
            }
        }
    }

    // MARK: - Scroll

    fun scroll(
        direction: String,
        containerId: String?,
    ) {
        MainThreadExecutor.runBlocking {
            val scrollView: View =
                if (containerId != null) {
                    val view = ElementInventory.findElement(containerId)
                    if (view == null || !isScrollable(view)) {
                        throw InteractionError.NotScrollable(containerId)
                    }
                    view
                } else {
                    findFirstScrollView()
                        ?: throw InteractionError.NoScrollView()
                }

            val dx: Int
            val dy: Int
            when (direction) {
                "up" -> {
                    dx = 0
                    dy = -(scrollView.height * 0.8).toInt()
                }

                "down" -> {
                    dx = 0
                    dy = (scrollView.height * 0.8).toInt()
                }

                "left" -> {
                    dx = -(scrollView.width * 0.8).toInt()
                    dy = 0
                }

                "right" -> {
                    dx = (scrollView.width * 0.8).toInt()
                    dy = 0
                }

                else -> {
                    throw InteractionError.NotScrollable("Invalid direction: $direction")
                }
            }

            when (scrollView) {
                is RecyclerView -> scrollView.smoothScrollBy(dx, dy)
                is ScrollView -> scrollView.smoothScrollBy(dx, dy)
                is NestedScrollView -> scrollView.smoothScrollBy(dx, dy)
                is HorizontalScrollView -> scrollView.smoothScrollBy(dx, dy)
                else -> throw InteractionError.NotScrollable(containerId ?: "auto")
            }
        }
    }

    fun scrollTo(elementId: String) {
        MainThreadExecutor.runBlocking {
            val view =
                ElementInventory.findElement(elementId)
                    ?: throw InteractionError.ElementNotFound(elementId)

            val parentScrollView = findParentScrollView(view)
            if (parentScrollView != null) {
                view.requestRectangleOnScreen(android.graphics.Rect(0, 0, view.width, view.height), false)
            }
        }
    }

    // MARK: - Tab switching

    fun selectTab(index: Int) {
        MainThreadExecutor.runBlocking {
            val activity =
                ScreenResolver.currentActivity
                    ?: throw InteractionError.NoNavigation()
            val decorView =
                activity.window?.decorView
                    ?: throw InteractionError.NoNavigation()

            val bottomNav =
                findViewOfType(decorView, BottomNavigationView::class.java)
                    ?: throw InteractionError.NoNavigation()

            val menu = bottomNav.menu
            if (index < 0 || index >= menu.size()) {
                throw InteractionError.ElementNotFound("tab_$index")
            }
            bottomNav.selectedItemId = menu.getItem(index).itemId
        }
    }

    // MARK: - Navigation

    fun navigateBack() {
        MainThreadExecutor.runBlocking {
            val activity =
                ScreenResolver.currentActivity
                    ?: throw InteractionError.NoNavigation()
            if (activity is ComponentActivity) {
                activity.onBackPressedDispatcher.onBackPressed()
            } else {
                @Suppress("DEPRECATION")
                activity.onBackPressed()
            }
        }
    }

    fun dismissModal() {
        MainThreadExecutor.runBlocking {
            val activity =
                ScreenResolver.currentActivity
                    ?: throw InteractionError.NoModal()

            // Check if this activity was started by another (has a parent or caller)
            if (activity.callingActivity != null || activity.isTaskRoot.not()) {
                activity.finish()
            } else {
                throw InteractionError.NoModal()
            }
        }
    }

    // MARK: - Helpers

    private fun isScrollable(view: View): Boolean =
        view is ScrollView || view is NestedScrollView ||
            view is RecyclerView || view is HorizontalScrollView

    private fun findFirstScrollView(): View? {
        val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return null
        return findScrollViewIn(decorView)
    }

    private fun findScrollViewIn(view: View): View? {
        if (isScrollable(view) && view !is EditText) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findScrollViewIn(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun findParentScrollView(view: View): View? {
        var current: View? = view.parent as? View
        while (current != null) {
            if (isScrollable(current)) return current
            current = current.parent as? View
        }
        return null
    }

    private fun <T : View> findViewOfType(
        root: View,
        clazz: Class<T>,
    ): T? {
        if (clazz.isInstance(root)) return clazz.cast(root)
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findViewOfType(root.getChildAt(i), clazz)
                if (found != null) return found
            }
        }
        return null
    }
}

/**
 * Interaction errors matching the iOS InteractionError cases.
 */
sealed class InteractionError(
    message: String,
) : Exception(message) {
    class ElementNotFound(
        id: String,
    ) : InteractionError("Element not found: $id")

    class NotEditable(
        id: String,
    ) : InteractionError("Element not editable: $id")

    class NotScrollable(
        id: String,
    ) : InteractionError("Element not scrollable: $id")

    class NoScrollView : InteractionError("No scroll view found")

    class NoNavigation : InteractionError("No navigation controller found")

    class NoModal : InteractionError("No modal to dismiss")
}
