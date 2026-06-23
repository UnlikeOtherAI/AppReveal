package com.appreveal.elements

import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import kotlin.math.max
import kotlin.math.min

/**
 * Traverses Jetpack Compose UI trees via the accessibility node provider.
 *
 * Compose renders its entire UI into a single AndroidComposeView (a custom View subclass).
 * Individual composables are NOT Android Views; they live in Compose's internal node tree.
 * However, Compose implements AccessibilityNodeProvider so TalkBack can read them — we use
 * the same API to enumerate and interact with composables without reflection or Compose deps.
 */
internal object ComposeElementInventory {
    fun listElements(root: View): List<ElementInfo> {
        val results = mutableListOf<ElementInfo>()
        val seenIds = mutableMapOf<String, Int>()
        forEachComposeView(root) { composeView ->
            traverseProviderTree(composeView, results, seenIds)
        }
        return results
    }

    fun findElementById(
        root: View,
        id: String,
    ): AccessibilityNodeInfoCompat? {
        var found: AccessibilityNodeInfoCompat? = null
        val seenIds = mutableMapOf<String, Int>()
        forEachComposeView(root) { composeView ->
            if (found != null) return@forEachComposeView
            val rootNode = rootNodeFor(composeView) ?: return@forEachComposeView
            found = findNodeById(rootNode, id, seenIds, composeView)
        }
        return found
    }

    fun findNodeByText(
        root: View,
        text: String,
        matchMode: String,
        occurrence: Int,
    ): AccessibilityNodeInfoCompat? {
        val candidates = mutableListOf<AccessibilityNodeInfoCompat>()
        forEachComposeView(root) { composeView ->
            val rootNode = rootNodeFor(composeView) ?: return@forEachComposeView
            collectNodesByText(rootNode, text, matchMode, candidates)
        }
        return candidates.getOrNull(occurrence)
    }

    fun findNodeAtPoint(
        root: View,
        x: Float,
        y: Float,
    ): AccessibilityNodeInfoCompat? {
        var best: AccessibilityNodeInfoCompat? = null
        var bestArea = Long.MAX_VALUE
        forEachComposeView(root) { composeView ->
            val rootNode = rootNodeFor(composeView) ?: return@forEachComposeView
            findNodeAtPoint(rootNode, x.toInt(), y.toInt()) { node, area ->
                if (area < bestArea) {
                    bestArea = area
                    best = node
                }
            }
        }
        return best
    }

    // MARK: - Private

    private fun forEachComposeView(
        root: View,
        action: (View) -> Unit,
    ) {
        if (isComposeView(root)) {
            action(root)
            return
        }
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                forEachComposeView(root.getChildAt(i), action)
            }
        }
    }

    private fun isComposeView(view: View): Boolean = view.javaClass.name.contains("AndroidComposeView")

    private fun rootNodeFor(composeView: View): AccessibilityNodeInfoCompat? {
        val provider = ViewCompat.getAccessibilityNodeProvider(composeView) ?: return null
        return provider.createAccessibilityNodeInfo(View.NO_ID)
    }

    private fun traverseProviderTree(
        composeView: View,
        results: MutableList<ElementInfo>,
        seenIds: MutableMap<String, Int>,
    ) {
        val rootNode = rootNodeFor(composeView) ?: return
        walkNode(rootNode, composeView, results, seenIds, containerId = null)
    }

    private fun walkNode(
        node: AccessibilityNodeInfoCompat,
        composeView: View,
        results: MutableList<ElementInfo>,
        seenIds: MutableMap<String, Int>,
        containerId: String?,
    ) {
        val label = nodeLabel(node)
        val isClickable = node.isClickable
        val isEditable = node.isEditable
        val isEnabled = node.isEnabled
        val isVisible = node.isVisibleToUser

        if (!isVisible) return

        if (label != null || isClickable || isEditable) {
            val rect = Rect()
            node.getBoundsInScreen(rect)

            if (!rect.isEmpty) {
                val rawId = nodeId(node, label)
                val finalId = deduplicatedId(rawId, seenIds)
                val frame =
                    ElementInfo.ElementFrame(
                        x = rect.left.toDouble(),
                        y = rect.top.toDouble(),
                        width = rect.width().toDouble(),
                        height = rect.height().toDouble(),
                    )
                val systemInsets = systemSafeAreaInsets(composeView)

                results.add(
                    ElementInfo(
                        id = finalId,
                        type = classifyNode(node),
                        label = label,
                        value = nodeValue(node),
                        enabled = isEnabled,
                        visible = isVisible,
                        tappable = isClickable,
                        frame = frame,
                        safeAreaInsets = safeAreaInsets(composeView, systemInsets),
                        safeAreaLayoutGuideFrame = safeAreaLayoutGuideFrame(frame, composeView, systemInsets),
                        containerId = containerId,
                        actions = nodeActions(node),
                        idSource = nodeIdSource(node),
                    ),
                )
            }
        }

        val currentContainerId = nodeId(node, label).takeIf { label != null } ?: containerId
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            walkNode(child, composeView, results, seenIds, currentContainerId)
        }
    }

    private fun findNodeById(
        node: AccessibilityNodeInfoCompat,
        targetId: String,
        seenIds: MutableMap<String, Int>,
        composeView: View,
    ): AccessibilityNodeInfoCompat? {
        val label = nodeLabel(node)
        val rawId = nodeId(node, label)
        val finalId = deduplicatedId(rawId, seenIds.toMutableMap())

        if (finalId == targetId || rawId == targetId) return node

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findNodeById(child, targetId, seenIds, composeView)
            if (found != null) return found
        }
        return null
    }

    private fun collectNodesByText(
        node: AccessibilityNodeInfoCompat,
        text: String,
        matchMode: String,
        results: MutableList<AccessibilityNodeInfoCompat>,
    ) {
        val label = nodeLabel(node)
        if (label != null) {
            val isMatch =
                when (matchMode) {
                    "contains" -> label.contains(text, ignoreCase = true)
                    else -> label.equals(text, ignoreCase = false)
                }
            if (isMatch && node.isClickable) {
                results.add(node)
            }
        }
        for (i in 0 until node.childCount) {
            collectNodesByText(node.getChild(i) ?: continue, text, matchMode, results)
        }
    }

    private fun findNodeAtPoint(
        node: AccessibilityNodeInfoCompat,
        x: Int,
        y: Int,
        visitor: (AccessibilityNodeInfoCompat, Long) -> Unit,
    ) {
        if (!node.isVisibleToUser) return
        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.contains(x, y) && node.isClickable) {
            visitor(node, rect.width().toLong() * rect.height().toLong())
        }
        for (i in 0 until node.childCount) {
            findNodeAtPoint(node.getChild(i) ?: continue, x, y, visitor)
        }
    }

    // MARK: - Node attribute helpers

    private fun nodeLabel(node: AccessibilityNodeInfoCompat): String? {
        val desc = node.contentDescription?.toString()?.takeIf { it.isNotBlank() }
        val text = node.text?.toString()?.takeIf { it.isNotBlank() }
        return desc ?: text
    }

    private fun nodeValue(node: AccessibilityNodeInfoCompat): String? {
        val text = node.text?.toString()?.takeIf { it.isNotBlank() }
        val desc = node.contentDescription?.toString()?.takeIf { it.isNotBlank() }
        return if (desc != null && text != null && desc != text) text else null
    }

    private fun nodeId(
        node: AccessibilityNodeInfoCompat,
        label: String?,
    ): String {
        val resId = node.viewIdResourceName?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
        return resId ?: ElementInventory.normalizeToId(label ?: node.className?.toString() ?: "compose_node")
    }

    private fun nodeIdSource(node: AccessibilityNodeInfoCompat): String {
        if (node.viewIdResourceName != null) return "explicit"
        if (node.contentDescription != null) return "semantics"
        if (node.text != null) return "text"
        return "derived"
    }

    private fun classifyNode(node: AccessibilityNodeInfoCompat): ElementType {
        val cls = node.className?.toString() ?: ""
        return when {
            cls.contains("EditText") || node.isEditable -> ElementType.TEXT_FIELD
            node.isClickable -> ElementType.BUTTON
            cls.contains("Switch") -> ElementType.TOGGLE
            cls.contains("Slider") || cls.contains("SeekBar") -> ElementType.SLIDER
            cls.contains("CheckBox") -> ElementType.TOGGLE
            cls.contains("RadioButton") -> ElementType.OTHER
            else -> ElementType.LABEL
        }
    }

    private fun systemSafeAreaInsets(view: View): Insets =
        ViewCompat.getRootWindowInsets(view)
            ?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            ?: Insets.NONE

    private fun safeAreaInsets(
        view: View,
        systemInsets: Insets,
    ): ElementInfo.ElementInsets {
        val isRightToLeft = ViewCompat.getLayoutDirection(view) == ViewCompat.LAYOUT_DIRECTION_RTL
        return ElementInfo.ElementInsets(
            top = systemInsets.top.toDouble(),
            leading = if (isRightToLeft) systemInsets.right.toDouble() else systemInsets.left.toDouble(),
            bottom = systemInsets.bottom.toDouble(),
            trailing = if (isRightToLeft) systemInsets.left.toDouble() else systemInsets.right.toDouble(),
        )
    }

    private fun safeAreaLayoutGuideFrame(
        frame: ElementInfo.ElementFrame,
        composeView: View,
        systemInsets: Insets,
    ): ElementInfo.ElementFrame {
        val rootView = composeView.rootView ?: return frame
        val rootLocation = IntArray(2)
        rootView.getLocationOnScreen(rootLocation)

        val safeLeft = rootLocation[0].toDouble() + systemInsets.left
        val safeTop = rootLocation[1].toDouble() + systemInsets.top
        val safeRight = rootLocation[0].toDouble() + rootView.width - systemInsets.right
        val safeBottom = rootLocation[1].toDouble() + rootView.height - systemInsets.bottom

        val x = max(frame.x, safeLeft)
        val y = max(frame.y, safeTop)
        val right = min(frame.x + frame.width, safeRight)
        val bottom = min(frame.y + frame.height, safeBottom)

        return ElementInfo.ElementFrame(
            x = x,
            y = y,
            width = max(0.0, right - x),
            height = max(0.0, bottom - y),
        )
    }

    private fun nodeActions(node: AccessibilityNodeInfoCompat): List<String> {
        val actions = mutableListOf<String>()
        if (node.isClickable) actions.add("tap")
        if (node.isLongClickable) actions.add("longPress")
        if (node.isEditable) {
            actions.add("type")
            actions.add("clear")
        }
        if (node.isScrollable) actions.add("scroll")
        return actions
    }

    private fun deduplicatedId(
        id: String,
        seenIds: MutableMap<String, Int>,
    ): String {
        val count = seenIds[id] ?: 0
        seenIds[id] = count + 1
        return if (count == 0) id else "${id}_$count"
    }
}

// Perform an accessibility action on a Compose node.
internal fun AccessibilityNodeInfoCompat.clickCompose(): Boolean {
    return performAction(AccessibilityNodeInfoCompat.ACTION_CLICK, Bundle())
}
