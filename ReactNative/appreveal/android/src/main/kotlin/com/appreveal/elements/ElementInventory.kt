package com.appreveal.elements

import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.ListView
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import androidx.appcompat.widget.Toolbar
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import com.appreveal.screen.ScreenResolver
import com.appreveal.shared.MainThreadExecutor
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.materialswitch.MaterialSwitch

/**
 * Enumerates visible interactive elements from the Android view hierarchy.
 * Adapted for React Native: uses ScreenResolver.currentActivity (backed by reactContext.currentActivity).
 * Does not use R.id.appreveal_id custom tag — uses resource name and content description only.
 */
internal object ElementInventory {

    fun listElements(): List<ElementInfo> {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking emptyList()
            val elements = mutableListOf<ElementInfo>()
            walkView(decorView, elements, null)
            elements
        }
    }

    fun findElement(id: String): View? {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking null
            findView(id, decorView)
        }
    }

    fun dumpViewTree(maxDepth: Int = 50): List<Map<String, Any>> {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking emptyList()
            dumpNode(decorView, 0, maxDepth)
        }
    }

    // -- Walking --

    private fun walkView(view: View, elements: MutableList<ElementInfo>, containerId: String?) {
        val id = resolveElementId(view)

        if (id != null || isInteractive(view)) {
            val info = makeElementInfo(view, id, containerId)
            if (info != null) {
                elements.add(info)
            }
        }

        val currentContainerId = id ?: containerId
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child.visibility != View.GONE) {
                    walkView(child, elements, currentContainerId)
                }
            }
        }
    }

    private fun isInteractive(view: View): Boolean {
        return view is Button ||
                view is EditText ||
                isSwitch(view) ||
                view is SeekBar
    }

    private fun makeElementInfo(view: View, id: String?, containerId: String?): ElementInfo? {
        if (id == null || id.isEmpty()) {
            if (!isInteractive(view)) return null
            return null
        }

        val location = IntArray(2)
        view.getLocationOnScreen(location)

        return ElementInfo(
            id = id,
            type = classifyView(view),
            label = view.contentDescription?.toString(),
            value = extractValue(view),
            enabled = view.isEnabled && (view.isClickable || view.isFocusable || view is EditText),
            visible = view.visibility == View.VISIBLE && view.alpha > 0f,
            tappable = view.isClickable || view.hasOnClickListeners(),
            frame = ElementInfo.ElementFrame(
                x = location[0].toDouble(),
                y = location[1].toDouble(),
                width = view.width.toDouble(),
                height = view.height.toDouble()
            ),
            containerId = containerId,
            actions = availableActions(view)
        )
    }

    internal fun resolveElementId(view: View): String? {
        // 1. Check resource entry name
        if (view.id != View.NO_ID) {
            try {
                val name = view.resources.getResourceEntryName(view.id)
                if (!name.isNullOrEmpty()) return name
            } catch (_: Exception) {
                // Resource not found
            }
        }

        // 2. Fall back to content description
        val desc = view.contentDescription?.toString()
        if (!desc.isNullOrEmpty()) return desc

        return null
    }

    private fun classifyView(view: View): ElementType {
        return when {
            view is Button || view.javaClass.simpleName.contains("MaterialButton") -> ElementType.BUTTON
            view is EditText -> ElementType.TEXT_FIELD
            view is TextView -> ElementType.LABEL
            view is ImageView -> ElementType.IMAGE
            isSwitch(view) -> ElementType.TOGGLE
            view is SeekBar -> ElementType.SLIDER
            view is RecyclerView -> ElementType.COLLECTION_VIEW
            view is ListView -> ElementType.TABLE_VIEW
            view is ScrollView || view is NestedScrollView || view is android.widget.HorizontalScrollView -> ElementType.SCROLL_VIEW
            view is Toolbar || view.javaClass.simpleName.contains("MaterialToolbar") -> ElementType.NAVIGATION_BAR
            view is BottomNavigationView -> ElementType.TAB_BAR
            else -> ElementType.OTHER
        }
    }

    private fun isSwitch(view: View): Boolean {
        return view is android.widget.Switch ||
                view.javaClass.simpleName == "SwitchCompat" ||
                view is MaterialSwitch
    }

    private fun extractValue(view: View): String? {
        return when (view) {
            is EditText -> view.text?.toString()
            is TextView -> view.text?.toString()
            is SeekBar -> view.progress.toString()
            else -> {
                if (isSwitch(view)) {
                    try {
                        val isChecked = view.javaClass.getMethod("isChecked").invoke(view) as? Boolean
                        isChecked?.toString()
                    } catch (_: Exception) { null }
                } else null
            }
        }
    }

    private fun availableActions(view: View): List<String> {
        val actions = mutableListOf<String>()
        if (view.isClickable || view.hasOnClickListeners()) {
            actions.add("tap")
        }
        if (view is EditText) {
            actions.add("type")
            actions.add("clear")
        }
        if (view is ScrollView || view is NestedScrollView || view is RecyclerView || view is android.widget.HorizontalScrollView) {
            actions.add("scroll")
        }
        return actions
    }

    // -- View tree dump --

    private fun dumpNode(view: View, depth: Int, maxDepth: Int): List<Map<String, Any>> {
        if (depth >= maxDepth) return emptyList()

        val location = IntArray(2)
        view.getLocationOnScreen(location)

        val node = mutableMapOf<String, Any>(
            "class" to view.javaClass.simpleName,
            "frame" to "${location[0]},${location[1]},${view.width},${view.height}",
            "hidden" to (view.visibility != View.VISIBLE),
            "alpha" to view.alpha,
            "userInteraction" to (view.isClickable || view.isFocusable),
            "depth" to depth
        )

        // Accessibility info
        val elementId = resolveElementId(view)
        if (!elementId.isNullOrEmpty()) {
            node["accessibilityId"] = elementId
        }
        val label = view.contentDescription?.toString()
        if (!label.isNullOrEmpty()) {
            node["accessibilityLabel"] = label
        }

        // Type-specific properties
        when (view) {
            is EditText -> {
                node["text"] = view.text?.toString() ?: ""
                node["hint"] = view.hint?.toString() ?: ""
                node["isEditing"] = view.isFocused
            }
            is TextView -> {
                node["text"] = view.text?.toString() ?: ""
                node["font"] = "${view.typeface} ${view.textSize}"
            }
            is Button -> {
                node["title"] = (view as TextView).text?.toString() ?: ""
                node["enabled"] = view.isEnabled
            }
            is ImageView -> {
                node["hasImage"] = view.drawable != null
            }
            is SeekBar -> {
                node["value"] = view.progress
                node["min"] = view.min
                node["max"] = view.max
            }
            else -> {
                if (isSwitch(view)) {
                    try {
                        val isChecked = view.javaClass.getMethod("isChecked").invoke(view) as? Boolean
                        if (isChecked != null) node["isOn"] = isChecked
                    } catch (_: Exception) {}
                }
                if (view.isClickable || view.isEnabled) {
                    node["enabled"] = view.isEnabled
                }
            }
        }

        val result = mutableListOf<Map<String, Any>>(node)
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                result.addAll(dumpNode(view.getChildAt(i), depth + 1, maxDepth))
            }
        }
        return result
    }

    private fun findView(id: String, view: View): View? {
        val viewId = resolveElementId(view)
        if (viewId == id) return view

        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findView(id, view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }
}
