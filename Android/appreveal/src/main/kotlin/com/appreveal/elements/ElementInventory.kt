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
import com.appreveal.R
import com.appreveal.screen.ScreenResolver
import com.appreveal.shared.MainThreadExecutor
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.materialswitch.MaterialSwitch

/**
 * Enumerates visible interactive elements from the Android view hierarchy.
 */
internal object ElementInventory {

    fun listElements(): List<ElementInfo> {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking emptyList()
            val elements = mutableListOf<ElementInfo>()
            val seenIds = mutableMapOf<String, Int>()
            walkView(decorView, elements, null, seenIds)
            elements
        }
    }

    fun findElement(id: String): View? {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking null
            // Try direct ID match first
            findView(id, decorView)
                // Try text-based lookup
                ?: findViewByNormalizedText(id, decorView)
                // Try semantics-based lookup
                ?: findViewByContentDescription(id, decorView)
        }
    }

    fun findElementByText(
        text: String,
        matchMode: String = "exact",
        occurrence: Int = 0
    ): Pair<View?, List<String>> {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView
                ?: return@runBlocking Pair(null, emptyList())

            val matches = mutableListOf<Pair<View, String>>()
            collectTextMatches(decorView, text, matchMode, matches)

            val candidates = matches.map { it.second }

            if (matches.isEmpty()) {
                return@runBlocking Pair(null, candidates)
            }

            if (occurrence >= matches.size) {
                return@runBlocking Pair(null, candidates)
            }

            val (matchedView, _) = matches[occurrence]

            // Walk up to find a tappable ancestor
            val tappable = findTappableAncestor(matchedView) ?: matchedView
            Pair(tappable, candidates)
        }
    }

    fun dumpViewTree(maxDepth: Int = 50): List<Map<String, Any>> {
        return MainThreadExecutor.runBlocking {
            val decorView = ScreenResolver.currentActivity?.window?.decorView ?: return@runBlocking emptyList()
            dumpNode(decorView, 0, maxDepth)
        }
    }

    // -- Text helpers --

    fun extractText(view: View): String? {
        return when (view) {
            is Button -> (view as TextView).text?.toString()
            is EditText -> view.hint?.toString() ?: view.text?.toString()
            is TextView -> view.text?.toString()
            else -> {
                // Walk immediate children for TextViews
                if (view is ViewGroup) {
                    for (i in 0 until view.childCount) {
                        val child = view.getChildAt(i)
                        if (child is TextView) return child.text?.toString()
                    }
                }
                null
            }
        }
    }

    fun normalizeToId(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return "unnamed"
        val normalized = trimmed.lowercase()
            .replace(Regex("\\s+"), "_")
            .replace(Regex("[^a-z0-9_]"), "")
        if (normalized.isEmpty()) return "unnamed"
        return normalized.take(40)
    }

    // -- Walking --

    private fun walkView(
        view: View,
        elements: MutableList<ElementInfo>,
        containerId: String?,
        seenIds: MutableMap<String, Int>
    ) {
        val info = makeElementInfo(view, containerId, seenIds)
        if (info != null) {
            elements.add(info)
        }

        val currentContainerId = info?.id ?: containerId
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child.visibility != View.GONE) {
                    walkView(child, elements, currentContainerId, seenIds)
                }
            }
        }
    }

    private fun isInteractive(view: View): Boolean {
        return view is Button ||
                view is EditText ||
                isSwitch(view) ||
                view is SeekBar ||
                view.isClickable ||
                view.hasOnClickListeners() ||
                view.isLongClickable
    }

    private fun makeElementInfo(
        view: View,
        containerId: String?,
        seenIds: MutableMap<String, Int>
    ): ElementInfo? {
        // Determine ID and source
        val tagId = view.getTag(R.id.appreveal_id) as? String
        var id: String?
        var idSource: String

        if (!tagId.isNullOrEmpty()) {
            id = tagId
            idSource = "explicit"
        } else if (view.id != View.NO_ID) {
            val name = try {
                view.resources.getResourceEntryName(view.id)
            } catch (_: Exception) { null }
            if (!name.isNullOrEmpty()) {
                id = name
                idSource = "explicit"
            } else {
                id = null
                idSource = "derived"
            }
        } else {
            id = null
            idSource = "derived"
        }

        // Try contentDescription if no explicit ID
        if (id == null) {
            val desc = view.contentDescription?.toString()
            if (!desc.isNullOrEmpty()) {
                id = normalizeToId(desc)
                idSource = "semantics"
            }
        }

        // Try visible text if still no ID
        if (id == null) {
            val text = extractText(view)
            if (!text.isNullOrEmpty()) {
                id = normalizeToId(text)
                idSource = "text"
            }
        }

        // For non-interactive views without any ID, skip
        if (id == null && !isInteractive(view)) return null

        // Generate a fallback derived ID for interactive views
        if (id == null) {
            val className = view.javaClass.simpleName.lowercase()
            id = className
            idSource = "derived"
        }

        // Deduplicate IDs
        val count = seenIds.getOrDefault(id, 0)
        seenIds[id] = count + 1
        if (count > 0) {
            id = "${id}_$count"
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
            actions = availableActions(view),
            idSource = idSource
        )
    }

    internal fun resolveElementId(view: View): String? {
        // 1. Check custom tag
        val tagId = view.getTag(R.id.appreveal_id) as? String
        if (!tagId.isNullOrEmpty()) return tagId

        // 2. Check resource entry name
        if (view.id != View.NO_ID) {
            try {
                val name = view.resources.getResourceEntryName(view.id)
                if (!name.isNullOrEmpty()) return name
            } catch (_: Exception) {
                // Resource not found
            }
        }

        // 3. Fall back to content description
        val desc = view.contentDescription?.toString()
        if (!desc.isNullOrEmpty()) return normalizeToId(desc)

        // 4. Fall back to visible text
        val text = extractText(view)
        if (!text.isNullOrEmpty()) return normalizeToId(text)

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

    // -- Text-based and semantics-based lookup --

    private fun collectTextMatches(
        view: View,
        text: String,
        matchMode: String,
        matches: MutableList<Pair<View, String>>
    ) {
        if (view is TextView) {
            val viewText = view.text?.toString() ?: ""
            val matched = when (matchMode) {
                "contains" -> viewText.contains(text, ignoreCase = true)
                else -> viewText.equals(text, ignoreCase = true)
            }
            if (matched) {
                matches.add(Pair(view, viewText))
            }
        }

        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                collectTextMatches(view.getChildAt(i), text, matchMode, matches)
            }
        }
    }

    private fun findTappableAncestor(view: View): View? {
        if (view.isClickable || view.hasOnClickListeners()) return view
        var parent: View? = view.parent as? View
        while (parent != null) {
            if (parent.isClickable || parent.hasOnClickListeners()) return parent
            parent = parent.parent as? View
        }
        return null
    }

    private fun findViewByNormalizedText(id: String, root: View): View? {
        val text = extractText(root)
        if (text != null && normalizeToId(text) == id) return root

        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findViewByNormalizedText(id, root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun findViewByContentDescription(id: String, root: View): View? {
        val desc = root.contentDescription?.toString()
        if (desc != null && normalizeToId(desc) == id) return root

        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findViewByContentDescription(id, root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
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
