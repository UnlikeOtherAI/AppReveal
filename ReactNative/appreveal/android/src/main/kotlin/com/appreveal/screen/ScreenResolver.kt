package com.appreveal.screen

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.fragment.app.Fragment
import com.appreveal.shared.MainThreadExecutor
import com.facebook.react.bridge.ReactApplicationContext
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.lang.ref.WeakReference

/**
 * Resolves screen identity for React Native.
 * Uses reactContext.currentActivity for activity access.
 * JS can set a screen key/title directly via setJsScreen(), which takes priority over
 * class-name-based detection.
 */
internal object ScreenResolver {

    private var reactContextRef: WeakReference<ReactApplicationContext>? = null

    // JS-provided screen info (highest confidence)
    @Volatile private var jsScreenKey: String? = null
    @Volatile private var jsScreenTitle: String? = null

    val currentActivity: Activity?
        get() = reactContextRef?.get()?.currentActivity

    val appContext: Context?
        get() = reactContextRef?.get()?.applicationContext

    fun init(reactContext: ReactApplicationContext) {
        reactContextRef = WeakReference(reactContext)
    }

    fun setJsScreen(key: String, title: String) {
        jsScreenKey = key
        jsScreenTitle = title
    }

    fun clearJsScreen() {
        jsScreenKey = null
        jsScreenTitle = null
    }

    fun resolve(): ScreenInfo {
        return MainThreadExecutor.runBlocking { resolveOnMainThread() }
    }

    private fun resolveOnMainThread(): ScreenInfo {
        // If JS has set a screen key, use it at confidence 1.0
        val jsKey = jsScreenKey
        val jsTitle = jsScreenTitle
        if (jsKey != null) {
            return ScreenInfo(
                screenKey = jsKey,
                screenTitle = jsTitle ?: jsKey,
                frameworkType = "react-native",
                activityChain = buildActivityChain(),
                activeTab = detectActiveTab(),
                navigationDepth = 0,
                presentedModals = emptyList(),
                confidence = 1.0,
                source = "explicit",
                appBarTitle = extractToolbarTitle(currentActivity)
            )
        }

        // Fall back to activity class name at confidence 0.8
        val activity = currentActivity
        if (activity == null) {
            return ScreenInfo(
                screenKey = "unknown",
                screenTitle = "Unknown",
                frameworkType = "unknown",
                activityChain = emptyList(),
                activeTab = null,
                navigationDepth = 0,
                presentedModals = emptyList(),
                confidence = 0.0,
                source = "derived",
                appBarTitle = null
            )
        }

        val className = activity.localClassName.substringAfterLast('.')
        val screenKey = deriveScreenKey(className)
        val title = activity.title?.toString() ?: deriveTitle(className)

        return ScreenInfo(
            screenKey = screenKey,
            screenTitle = title,
            frameworkType = "react-native",
            activityChain = buildActivityChain(),
            activeTab = detectActiveTab(),
            navigationDepth = 0,
            presentedModals = emptyList(),
            confidence = 0.8,
            source = "derived",
            appBarTitle = extractToolbarTitle(activity)
        )
    }

    private fun buildActivityChain(): List<String> {
        val activity = currentActivity ?: return emptyList()
        return listOf(activity.javaClass.simpleName)
    }

    private fun detectActiveTab(): String? {
        val activity = currentActivity ?: return null
        val decorView = activity.window?.decorView ?: return null
        val bottomNav = findViewOfType(decorView, BottomNavigationView::class.java) ?: return null
        val selectedId = bottomNav.selectedItemId
        val menu = bottomNav.menu
        for (i in 0 until menu.size()) {
            val item = menu.getItem(i)
            if (item.itemId == selectedId) {
                return item.title?.toString()
            }
        }
        return null
    }

    private fun <T : View> findViewOfType(root: View, clazz: Class<T>): T? {
        if (clazz.isInstance(root)) return clazz.cast(root)
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findViewOfType(root.getChildAt(i), clazz)
                if (found != null) return found
            }
        }
        return null
    }

    private fun extractToolbarTitle(activity: Activity?): String? {
        if (activity == null) return null
        val decorView = activity.window?.decorView ?: return null
        val toolbar = findViewOfType(decorView, Toolbar::class.java)
        if (toolbar?.title != null) return toolbar.title.toString()
        if (activity is AppCompatActivity) {
            val actionBarTitle = activity.supportActionBar?.title?.toString()
            if (!actionBarTitle.isNullOrEmpty()) return actionBarTitle
        }
        return activity.actionBar?.title?.toString()
    }

    /**
     * "OrderDetailFragment" -> "order.detail"
     * "LoginActivity" -> "login"
     * "ProductListVC" -> "product.list"
     */
    fun deriveScreenKey(className: String): String {
        var name = className
        for (suffix in listOf("ViewController", "Controller", "Fragment", "Activity", "Screen", "View", "VC")) {
            if (name.endsWith(suffix) && name.length > suffix.length) {
                name = name.dropLast(suffix.length)
                break
            }
        }
        val parts = splitCamelCase(name)
        return parts.joinToString(".") { it.lowercase() }
    }

    /**
     * "OrderDetailFragment" -> "Order Detail"
     */
    fun deriveTitle(className: String): String {
        var name = className
        for (suffix in listOf("ViewController", "Controller", "Fragment", "Activity", "Screen", "View", "VC")) {
            if (name.endsWith(suffix) && name.length > suffix.length) {
                name = name.dropLast(suffix.length)
                break
            }
        }
        return splitCamelCase(name).joinToString(" ")
    }

    private fun splitCamelCase(string: String): List<String> {
        val parts = mutableListOf<String>()
        var current = StringBuilder()
        for (char in string) {
            if (char.isUpperCase() && current.isNotEmpty()) {
                parts.add(current.toString())
                current = StringBuilder()
            }
            current.append(char)
        }
        if (current.isNotEmpty()) parts.add(current.toString())
        return parts
    }
}
