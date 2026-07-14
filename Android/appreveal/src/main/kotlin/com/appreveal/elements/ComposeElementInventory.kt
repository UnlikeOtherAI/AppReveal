package com.appreveal.elements

import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.accessibility.AccessibilityNodeProviderCompat
import kotlin.math.max
import kotlin.math.min

/** Result of trying to edit a Compose semantics node. */
internal enum class ComposeTextActionResult {
    SUCCESS,
    NOT_FOUND,
    NOT_EDITABLE,
    ACTION_FAILED,
}

/** A text match and the semantics action that should receive its tap. */
internal data class ComposeTextMatch(
    val matchedText: String,
    internal val action: Any?,
    internal val provider: AccessibilityNodeProviderCompat?,
    internal val actionNodeId: Int?,
)

/**
 * Traverses Jetpack Compose through its semantics tree without taking a Compose dependency.
 *
 * Accessibility nodes created in the app process cannot safely recurse with `getChild()` on
 * Android 26-33. Instead, this bridge reflects the stable JVM-facing semantics accessors on
 * AndroidComposeView, then asks the view's accessibility provider for each known semantics ID.
 * Actions invoke the node's semantics callback directly, with the accessibility provider retained
 * as a fallback when Android accessibility is active.
 */
internal object ComposeElementInventory {
    fun listElements(
        root: View,
        seenIds: MutableMap<String, Int>,
    ): List<ElementInfo> = snapshot(root, seenIds).map { it.elementInfo }

    fun tapElementById(
        root: View,
        id: String,
        seenIds: MutableMap<String, Int>,
    ): Boolean? {
        val handle = snapshot(root, seenIds).firstOrNull { it.elementInfo.id == id } ?: return null
        if (!handle.clickable) return false
        if (invokeSemanticsAction(handle.clickAction)) return true
        return handle.provider?.performAction(handle.semanticsId, AccessibilityNodeInfo.ACTION_CLICK, null) ?: false
    }

    fun findTextMatches(
        root: View,
        text: String,
        matchMode: String,
        seenIds: MutableMap<String, Int>,
    ): List<ComposeTextMatch> {
        val handles = snapshot(root, seenIds)
        val handlesByNodeId = handles.associateBy { it.semanticsId }

        return handles.mapNotNull { handle ->
            val matchedText =
                handle.searchableTexts.firstOrNull { candidate ->
                    when (matchMode) {
                        "contains" -> candidate.contains(text, ignoreCase = true)
                        else -> candidate.equals(text, ignoreCase = true)
                    }
                } ?: return@mapNotNull null

            var actionHandle: NodeHandle? = handle
            while (actionHandle != null && !actionHandle.clickable) {
                actionHandle = actionHandle.parentSemanticsId?.let(handlesByNodeId::get)
            }

            ComposeTextMatch(
                matchedText = matchedText,
                action = actionHandle?.clickAction,
                provider = actionHandle?.provider,
                actionNodeId = actionHandle?.semanticsId,
            )
        }
    }

    fun tapTextMatch(match: ComposeTextMatch): Boolean {
        if (invokeSemanticsAction(match.action)) return true
        val provider = match.provider ?: return false
        val nodeId = match.actionNodeId ?: return false
        return provider.performAction(nodeId, AccessibilityNodeInfo.ACTION_CLICK, null)
    }

    fun typeTextById(
        root: View,
        id: String,
        text: String,
        append: Boolean,
        seenIds: MutableMap<String, Int>,
    ): ComposeTextActionResult {
        val handle =
            snapshot(root, seenIds).firstOrNull { it.elementInfo.id == id }
                ?: return ComposeTextActionResult.NOT_FOUND
        return setText(handle, text, append)
    }

    fun typeTextInFocusedElement(
        root: View,
        text: String,
        append: Boolean,
        seenIds: MutableMap<String, Int>,
    ): ComposeTextActionResult {
        val handle =
            snapshot(root, seenIds).firstOrNull { it.focused && it.editable }
                ?: return ComposeTextActionResult.NOT_FOUND
        return setText(handle, text, append)
    }

    fun dumpTreeForComposeView(
        composeView: View,
        depth: Int,
        maxDepth: Int,
    ): List<Map<String, Any>> {
        if (!isComposeView(composeView) || depth >= maxDepth) return emptyList()
        val provider = ViewCompat.getAccessibilityNodeProvider(composeView)
        val rootNode = semanticsRootFor(composeView) ?: return emptyList()
        val result = mutableListOf<Map<String, Any>>()
        dumpSemanticsNode(rootNode, composeView, provider, depth, maxDepth, result)
        return result
    }

    fun isComposeView(view: View): Boolean = view.javaClass.name.contains("AndroidComposeView")

    private data class NodeHandle(
        val semanticsId: Int,
        val parentSemanticsId: Int?,
        val provider: AccessibilityNodeProviderCompat?,
        val elementInfo: ElementInfo,
        val searchableTexts: List<String>,
        val editable: Boolean,
        val focused: Boolean,
        val clickable: Boolean,
        val currentText: String?,
        val editableTextTemplate: Any?,
        val clickAction: Any?,
        val setTextAction: Any?,
    )

    private data class SemanticsProperties(
        var testTag: String? = null,
        var visibleText: List<String> = emptyList(),
        var editableText: String? = null,
        var contentDescriptions: List<String> = emptyList(),
        var role: String? = null,
        var hasOnClick: Boolean = false,
        var hasSetText: Boolean = false,
        var disabled: Boolean = false,
        var focused: Boolean = false,
        var invisibleToUser: Boolean = false,
        var scrollable: Boolean = false,
        var editableTextTemplate: Any? = null,
        var clickAction: Any? = null,
        var setTextAction: Any? = null,
    ) {
        val searchableTexts: List<String>
            get() = (contentDescriptions + visibleText + listOfNotNull(editableText)).filter { it.isNotBlank() }.distinct()
    }

    private fun snapshot(
        root: View,
        seenIds: MutableMap<String, Int>,
    ): List<NodeHandle> {
        val results = mutableListOf<NodeHandle>()
        forEachComposeView(root) { composeView ->
            val semanticsRoot = semanticsRootFor(composeView) ?: return@forEachComposeView
            val provider = ViewCompat.getAccessibilityNodeProvider(composeView)
            walkSemanticsNode(
                node = semanticsRoot,
                composeView = composeView,
                provider = provider,
                parentSemanticsId = null,
                containerId = null,
                seenIds = seenIds,
                results = results,
            )
        }
        return results
    }

    private fun walkSemanticsNode(
        node: Any,
        composeView: View,
        provider: AccessibilityNodeProviderCompat?,
        parentSemanticsId: Int?,
        containerId: String?,
        seenIds: MutableMap<String, Int>,
        results: MutableList<NodeHandle>,
    ) {
        val semanticsId = semanticsId(node) ?: return
        val properties = semanticsProperties(node)
        val accessibilityInfo = createAccessibilityNodeInfo(provider, semanticsId)
        val bounds = boundsFor(node, composeView, accessibilityInfo)
        val visible =
            !properties.invisibleToUser &&
                (accessibilityInfo?.isVisibleToUser ?: (composeView.isShown && !bounds.isEmpty))
        val clickable = properties.hasOnClick || accessibilityInfo?.isClickable == true
        val editable = properties.hasSetText || accessibilityInfo?.isEditable == true
        val label =
            properties.contentDescriptions.firstOrNull()
                ?: properties.visibleText.firstOrNull()
                ?: accessibilityInfo?.contentDescription?.toString()?.takeIf { it.isNotBlank() }
                ?: accessibilityInfo?.text?.toString()?.takeIf { it.isNotBlank() }
        val currentText =
            properties.editableText
                ?: accessibilityInfo?.text?.toString()?.takeIf { it.isNotBlank() }
        val shouldList = visible && !bounds.isEmpty && (properties.testTag != null || label != null || clickable || editable)

        var currentContainerId = containerId
        if (shouldList) {
            val rawId = nodeId(semanticsId, properties, accessibilityInfo, label)
            val finalId = deduplicatedId(rawId.first, seenIds)
            val frame = bounds.toElementFrame()
            val systemInsets = systemSafeAreaInsets(composeView)
            val enabled = !properties.disabled && (accessibilityInfo?.isEnabled ?: true)
            val actions = nodeActions(properties, accessibilityInfo, clickable, editable)
            val elementInfo =
                ElementInfo(
                    id = finalId,
                    type = classifyNode(properties, accessibilityInfo, editable, clickable),
                    label = label,
                    value = currentText?.takeIf { it != label },
                    enabled = enabled,
                    visible = visible,
                    tappable = clickable,
                    frame = frame,
                    safeAreaInsets = safeAreaInsets(composeView, systemInsets),
                    safeAreaLayoutGuideFrame = safeAreaLayoutGuideFrame(frame, composeView, systemInsets),
                    containerId = containerId,
                    actions = actions,
                    idSource = rawId.second,
                )
            results.add(
                NodeHandle(
                    semanticsId = semanticsId,
                    parentSemanticsId = parentSemanticsId,
                    provider = provider,
                    elementInfo = elementInfo,
                    searchableTexts = properties.searchableTexts.ifEmpty { listOfNotNull(label, currentText) }.distinct(),
                    editable = editable,
                    focused = properties.focused || accessibilityInfo?.isFocused == true,
                    clickable = clickable,
                    currentText = currentText,
                    editableTextTemplate = properties.editableTextTemplate,
                    clickAction = properties.clickAction,
                    setTextAction = properties.setTextAction,
                ),
            )
            currentContainerId = finalId
        }

        semanticsChildren(node).forEach { child ->
            walkSemanticsNode(
                node = child,
                composeView = composeView,
                provider = provider,
                parentSemanticsId = if (shouldList) semanticsId else parentSemanticsId,
                containerId = currentContainerId,
                seenIds = seenIds,
                results = results,
            )
        }
    }

    private fun setText(
        handle: NodeHandle,
        text: String,
        append: Boolean,
    ): ComposeTextActionResult {
        if (!handle.editable) return ComposeTextActionResult.NOT_EDITABLE
        val replacement = if (append) handle.currentText.orEmpty() + text else text
        val annotatedString = annotatedString(handle.editableTextTemplate, replacement)
        if (annotatedString != null && invokeSemanticsAction(handle.setTextAction, annotatedString)) {
            return ComposeTextActionResult.SUCCESS
        }
        val provider = handle.provider ?: return ComposeTextActionResult.ACTION_FAILED
        val arguments =
            Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, replacement)
            }
        return if (provider.performAction(handle.semanticsId, AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) {
            ComposeTextActionResult.SUCCESS
        } else {
            ComposeTextActionResult.ACTION_FAILED
        }
    }

    private fun forEachComposeView(
        root: View,
        action: (View) -> Unit,
    ) {
        if (isComposeView(root)) {
            action(root)
            return
        }
        if (root is ViewGroup) {
            for (index in 0 until root.childCount) {
                forEachComposeView(root.getChildAt(index), action)
            }
        }
    }

    private fun semanticsRootFor(composeView: View): Any? {
        val owner = invokeNoArg(composeView, "getSemanticsOwner") ?: return null
        return invokeNoArg(owner, "getRootSemanticsNode")
    }

    private fun semanticsId(node: Any): Int? = (invokeNoArg(node, "getId") as? Number)?.toInt()

    private fun semanticsChildren(node: Any): List<Any> {
        val children = invokeNoArg(node, "getChildren") as? Iterable<*> ?: return emptyList()
        return children.filterNotNull()
    }

    private fun semanticsProperties(node: Any): SemanticsProperties {
        val properties = SemanticsProperties()
        val config = invokeNoArg(node, "getConfig") as? Iterable<*> ?: return properties
        config.forEach { item ->
            val entry = item as? Map.Entry<*, *> ?: return@forEach
            val key = entry.key ?: return@forEach
            val name = invokeNoArg(key, "getName") as? String ?: return@forEach
            val value = entry.value
            when (name) {
                "TestTag" -> properties.testTag = value?.toString()?.takeIf { it.isNotBlank() }
                "Text" -> properties.visibleText = semanticsTextList(value)
                "EditableText" -> {
                    properties.editableText = value?.toString()
                    properties.editableTextTemplate = value
                }
                "ContentDescription" -> properties.contentDescriptions = semanticsTextList(value)
                "Role" -> properties.role = value?.toString()
                "OnClick" -> {
                    properties.hasOnClick = true
                    properties.clickAction = accessibilityAction(value)
                }
                "SetText" -> {
                    properties.hasSetText = true
                    properties.setTextAction = accessibilityAction(value)
                }
                "Disabled" -> properties.disabled = true
                "Focused" -> properties.focused = value as? Boolean ?: false
                "InvisibleToUser", "HideFromAccessibility" -> properties.invisibleToUser = true
                "ScrollBy", "ScrollToIndex", "HorizontalScrollAxisRange", "VerticalScrollAxisRange" -> {
                    properties.scrollable = true
                }
            }
        }
        return properties
    }

    private fun semanticsTextList(value: Any?): List<String> =
        when (value) {
            is Iterable<*> -> value.mapNotNull { it?.toString()?.takeIf(String::isNotBlank) }
            null -> emptyList()
            else -> listOf(value.toString()).filter(String::isNotBlank)
        }

    private fun invokeNoArg(
        target: Any,
        methodName: String,
    ): Any? =
        try {
            target.javaClass.methods
                .firstOrNull { it.name == methodName && it.parameterCount == 0 }
                ?.invoke(target)
        } catch (_: ReflectiveOperationException) {
            null
        } catch (_: RuntimeException) {
            null
        }

    private fun accessibilityAction(value: Any?): Any? = value?.let { invokeNoArg(it, "getAction") }

    private fun invokeSemanticsAction(
        action: Any?,
        argument: Any? = null,
    ): Boolean {
        if (action == null) return false
        return try {
            val parameterCount = if (argument == null) 0 else 1
            val method =
                action.javaClass.methods.firstOrNull {
                    it.name == "invoke" && it.parameterCount == parameterCount && !it.isBridge
                } ?: action.javaClass.methods.firstOrNull {
                    it.name == "invoke" && it.parameterCount == parameterCount
                } ?: return false
            val result = if (argument == null) method.invoke(action) else method.invoke(action, argument)
            result as? Boolean ?: false
        } catch (_: ReflectiveOperationException) {
            false
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun annotatedString(
        template: Any?,
        text: String,
    ): Any? {
        val type = template?.javaClass ?: return null
        return try {
            val constructor =
                type.constructors
                    .filter { candidate ->
                        candidate.parameterTypes.firstOrNull() == String::class.java &&
                            candidate.parameterTypes.drop(1).all { List::class.java.isAssignableFrom(it) }
                    }
                    .minByOrNull { it.parameterCount }
                    ?: return null
            val arguments = arrayOfNulls<Any>(constructor.parameterCount)
            arguments[0] = text
            for (index in 1 until arguments.size) arguments[index] = emptyList<Any>()
            constructor.newInstance(*arguments)
        } catch (_: ReflectiveOperationException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun createAccessibilityNodeInfo(
        provider: AccessibilityNodeProviderCompat?,
        semanticsId: Int,
    ): AccessibilityNodeInfoCompat? =
        try {
            provider?.createAccessibilityNodeInfo(semanticsId)
        } catch (_: RuntimeException) {
            null
        }

    private fun boundsFor(
        node: Any,
        composeView: View,
        accessibilityInfo: AccessibilityNodeInfoCompat?,
    ): Rect {
        val accessibilityBounds = Rect()
        accessibilityInfo?.getBoundsInScreen(accessibilityBounds)
        if (!accessibilityBounds.isEmpty) return accessibilityBounds

        val composeBounds = invokeNoArg(node, "getBoundsInRoot") ?: return accessibilityBounds
        val left = (invokeNoArg(composeBounds, "getLeft") as? Number)?.toFloat() ?: return accessibilityBounds
        val top = (invokeNoArg(composeBounds, "getTop") as? Number)?.toFloat() ?: return accessibilityBounds
        val right = (invokeNoArg(composeBounds, "getRight") as? Number)?.toFloat() ?: return accessibilityBounds
        val bottom = (invokeNoArg(composeBounds, "getBottom") as? Number)?.toFloat() ?: return accessibilityBounds
        val location = IntArray(2)
        composeView.getLocationOnScreen(location)
        return Rect(
            (location[0] + left).toInt(),
            (location[1] + top).toInt(),
            (location[0] + right).toInt(),
            (location[1] + bottom).toInt(),
        )
    }

    private fun nodeId(
        semanticsId: Int,
        properties: SemanticsProperties,
        accessibilityInfo: AccessibilityNodeInfoCompat?,
        label: String?,
    ): Pair<String, String> {
        properties.testTag?.let { return Pair(it, "explicit") }
        accessibilityInfo?.viewIdResourceName
            ?.substringAfterLast('/')
            ?.takeIf { it.isNotBlank() }
            ?.let { return Pair(it, "explicit") }
        properties.contentDescriptions.firstOrNull()?.let {
            return Pair(ElementInventory.normalizeToId(it), "semantics")
        }
        properties.visibleText.firstOrNull()?.let {
            return Pair(ElementInventory.normalizeToId(it), "text")
        }
        properties.editableText?.takeIf { it.isNotBlank() }?.let {
            return Pair(ElementInventory.normalizeToId(it), "text")
        }
        label?.let { return Pair(ElementInventory.normalizeToId(it), "text") }
        return Pair("compose_$semanticsId", "derived")
    }

    private fun classifyNode(
        properties: SemanticsProperties,
        accessibilityInfo: AccessibilityNodeInfoCompat?,
        editable: Boolean,
        clickable: Boolean,
    ): ElementType {
        val className = accessibilityInfo?.className?.toString().orEmpty()
        val role = properties.role.orEmpty()
        return when {
            editable || className.contains("EditText") -> ElementType.TEXT_FIELD
            role.contains("Switch", ignoreCase = true) ||
                role.contains("Checkbox", ignoreCase = true) ||
                className.contains("Switch") ||
                className.contains("CheckBox") -> ElementType.TOGGLE
            role.contains("Image", ignoreCase = true) || className.contains("Image") -> ElementType.IMAGE
            role.contains("Tab", ignoreCase = true) -> ElementType.OTHER
            role.contains("Button", ignoreCase = true) || clickable -> ElementType.BUTTON
            className.contains("Slider") || className.contains("SeekBar") -> ElementType.SLIDER
            else -> ElementType.LABEL
        }
    }

    private fun nodeActions(
        properties: SemanticsProperties,
        accessibilityInfo: AccessibilityNodeInfoCompat?,
        clickable: Boolean,
        editable: Boolean,
    ): List<String> {
        val actions = mutableListOf<String>()
        if (clickable) actions.add("tap")
        if (accessibilityInfo?.isLongClickable == true) actions.add("longPress")
        if (editable) {
            actions.add("type")
            actions.add("clear")
        }
        if (properties.scrollable || accessibilityInfo?.isScrollable == true) actions.add("scroll")
        return actions
    }

    private fun dumpSemanticsNode(
        node: Any,
        composeView: View,
        provider: AccessibilityNodeProviderCompat?,
        depth: Int,
        maxDepth: Int,
        results: MutableList<Map<String, Any>>,
    ) {
        if (depth >= maxDepth) return
        val semanticsId = semanticsId(node) ?: return
        val properties = semanticsProperties(node)
        val accessibilityInfo = createAccessibilityNodeInfo(provider, semanticsId)
        val bounds = boundsFor(node, composeView, accessibilityInfo)
        val label =
            properties.contentDescriptions.firstOrNull()
                ?: properties.visibleText.firstOrNull()
                ?: accessibilityInfo?.contentDescription?.toString()?.takeIf { it.isNotBlank() }
        val rawId = nodeId(semanticsId, properties, accessibilityInfo, label).first
        val frame = bounds.toElementFrame()
        val systemInsets = systemSafeAreaInsets(composeView)
        val visible =
            !properties.invisibleToUser &&
                (accessibilityInfo?.isVisibleToUser ?: (composeView.isShown && !bounds.isEmpty))
        val clickable = properties.hasOnClick || accessibilityInfo?.isClickable == true
        val editable = properties.hasSetText || accessibilityInfo?.isEditable == true
        val nodeMap =
            mutableMapOf<String, Any>(
                "class" to "Compose.${accessibilityInfo?.className?.toString()?.substringAfterLast('.') ?: "SemanticsNode"}",
                "frame" to "${bounds.left},${bounds.top},${bounds.width()},${bounds.height()}",
                "safeAreaInsets" to safeAreaInsets(composeView, systemInsets).toMap(),
                "safeAreaLayoutGuideFrame" to safeAreaLayoutGuideFrame(frame, composeView, systemInsets).toMap(),
                "hidden" to !visible,
                "alpha" to 1.0f,
                "userInteraction" to (clickable || editable),
                "depth" to depth,
                "virtual" to true,
                "framework" to "compose",
                "semanticsId" to semanticsId,
                "accessibilityId" to rawId,
                "enabled" to (!properties.disabled && (accessibilityInfo?.isEnabled ?: true)),
                "focused" to (properties.focused || accessibilityInfo?.isFocused == true),
                "editable" to editable,
                "actions" to nodeActions(properties, accessibilityInfo, clickable, editable).joinToString(","),
            )
        label?.let { nodeMap["accessibilityLabel"] = it }
        properties.visibleText.firstOrNull()?.let { nodeMap["text"] = it }
        properties.editableText?.let { nodeMap["value"] = it }
        results.add(nodeMap)

        semanticsChildren(node).forEach { child ->
            dumpSemanticsNode(child, composeView, provider, depth + 1, maxDepth, results)
        }
    }

    private fun Rect.toElementFrame(): ElementInfo.ElementFrame =
        ElementInfo.ElementFrame(
            x = left.toDouble(),
            y = top.toDouble(),
            width = width().toDouble(),
            height = height().toDouble(),
        )

    private fun ElementInfo.ElementInsets.toMap(): Map<String, Double> =
        mapOf(
            "top" to top,
            "leading" to leading,
            "bottom" to bottom,
            "trailing" to trailing,
        )

    private fun ElementInfo.ElementFrame.toMap(): Map<String, Double> =
        mapOf(
            "x" to x,
            "y" to y,
            "width" to width,
            "height" to height,
        )

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

    private fun deduplicatedId(
        id: String,
        seenIds: MutableMap<String, Int>,
    ): String {
        val count = seenIds[id] ?: 0
        seenIds[id] = count + 1
        return if (count == 0) id else "${id}_$count"
    }
}
