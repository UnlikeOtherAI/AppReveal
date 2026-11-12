package com.appreveal.elements

import android.app.Activity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import com.appreveal.R
import com.appreveal.screen.ScreenResolver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ElementInventoryTest {
    private lateinit var activity: Activity
    private lateinit var content: LinearLayout

    @Before fun setUp() {
        ScreenResolver.init(RuntimeEnvironment.getApplication())
        activity = Robolectric.buildActivity(Activity::class.java).setup().visible().get()
        content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        activity.setContentView(content)
    }

    private fun layout() {
        activity.window.decorView.measure(View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1200, View.MeasureSpec.EXACTLY))
        activity.window.decorView.layout(0, 0, 800, 1200)
    }

    @Test fun switchReportsCheckedStateAndDuplicateIdsRoundTrip() {
        val toggle =
            Switch(activity).apply {
                setTag(R.id.appreveal_id, "toggle")
                isChecked = true
            }
        var selected = ""
        val first =
            Button(activity).apply {
                text = "Duplicate"
                setOnClickListener { selected = "first" }
            }
        val second =
            Button(activity).apply {
                text = "Duplicate"
                setOnClickListener { selected = "second" }
            }
        content.addView(toggle)
        content.addView(first)
        content.addView(second)
        layout()
        val info = ElementInventory.listElements().first { it.id == "toggle" }
        assertEquals(ElementType.TOGGLE, info.type)
        assertEquals("true", info.value)
        assertTrue(ElementInventory.tapElementById("toggle"))
        assertFalse(toggle.isChecked)
        val secondId = ElementInventory.listElements().filter { it.type == ElementType.BUTTON }.last().id
        assertTrue(ElementInventory.tapElementById(secondId))
        assertEquals("second", selected)
    }

    @Test fun disabledAndHiddenControlsDoNotMutate() {
        var clicked = false
        val button =
            Button(activity).apply {
                text = "Disabled"
                setTag(R.id.appreveal_id, "test.disabled")
                setOnClickListener { clicked = true }
                isEnabled = false
            }
        val field =
            EditText(activity).apply {
                setTag(R.id.appreveal_id, "field")
                setText("original")
                isEnabled = false
            }
        content.addView(button)
        content.addView(field)
        layout()
        assertFalse(ElementInventory.tapElementById("test.disabled"))
        assertFalse(ElementInventory.tapElementByText("Disabled")["success"] as Boolean)
        assertEquals(ElementTextActionResult.NOT_EDITABLE, ElementInventory.typeText("changed", "field"))
        assertEquals(ElementTextActionResult.NOT_EDITABLE, ElementInventory.clearText("field"))
        assertFalse(clicked)
        assertEquals("original", field.text.toString())
        button.isEnabled = true
        content.alpha = 0f
        assertFalse(ElementInventory.tapElementById("test.disabled"))
        content.alpha = 1f
        assertTrue(ElementInventory.tapElementById("test.disabled"))
        assertTrue(clicked)
    }
}
