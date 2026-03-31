package com.appreveal.elements

/**
 * Type of UI element. Values match iOS ElementType rawValue exactly.
 */
enum class ElementType(val value: String) {
    BUTTON("button"),
    TEXT_FIELD("textField"),
    LABEL("label"),
    IMAGE("image"),
    TOGGLE("toggle"),
    SLIDER("slider"),
    STEPPER("stepper"),
    PICKER("picker"),
    SCROLL_VIEW("scrollView"),
    TABLE_VIEW("tableView"),
    COLLECTION_VIEW("collectionView"),
    CELL("cell"),
    NAVIGATION_BAR("navigationBar"),
    TAB_BAR("tabBar"),
    OTHER("other")
}

/**
 * Describes a visible interactive element on screen.
 * Matches iOS ElementInfo exactly.
 */
data class ElementInfo(
    val id: String,
    val type: ElementType,
    val label: String?,
    val value: String?,
    val enabled: Boolean,
    val visible: Boolean,
    val tappable: Boolean,
    val frame: ElementFrame,
    val containerId: String?,
    val actions: List<String>,
    /** How the id was derived: "explicit", "text", "semantics", "derived" */
    val idSource: String
) {
    data class ElementFrame(
        val x: Double,
        val y: Double,
        val width: Double,
        val height: Double
    )
}
