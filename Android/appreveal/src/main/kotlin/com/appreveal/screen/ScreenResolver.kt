package com.appreveal.screen

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.fragment.app.Fragment
import com.appreveal.shared.MainThreadExecutor
import com.google.android.material.bottomnavigation.BottomNavigationView
import java.lang.ref.WeakReference

/**
 * Tracks the current Activity via ActivityLifecycleCallbacks and resolves screen identity.
 */
internal object ScreenResolver {

    private var currentActivityRef: WeakReference<Activity>? = null

    val currentActivity: Activity?
        get() = currentActivityRef?.get()

    fun init(application: Application) {
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                currentActivityRef = WeakReference(activity)
            }
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {
                if (currentActivityRef?.get() === activity) {
                    currentActivityRef = null
                }
            }
        })
    }

    fun resolve(): ScreenInfo {
        return MainThreadExecutor.runBlocking { resolveOnMainThread() }
    }

    private fun resolveOnMainThread(): ScreenInfo {
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

        // Check topmost fragment first (if AppCompatActivity)
        val topFragment = findTopFragment(activity)

        // Check if fragment implements ScreenIdentifiable
        if (topFragment is ScreenIdentifiable) {
            return ScreenInfo(
                screenKey = topFragment.screenKey,
                screenTitle = topFragment.screenTitle,
                frameworkType = detectFrameworkType(activity),
                activityChain = buildActivityChain(activity, topFragment),
                activeTab = detectActiveTab(activity),
                navigationDepth = getNavigationDepth(activity),
                presentedModals = emptyList(),
                confidence = 1.0,
                source = "explicit",
                appBarTitle = extractToolbarTitle(activity)
            )
        }

        // Check if activity implements ScreenIdentifiable
        if (activity is ScreenIdentifiable) {
            return ScreenInfo(
                screenKey = activity.screenKey,
                screenTitle = activity.screenTitle,
                frameworkType = detectFrameworkType(activity),
                activityChain = buildActivityChain(activity, topFragment),
                activeTab = detectActiveTab(activity),
                navigationDepth = getNavigationDepth(activity),
                presentedModals = emptyList(),
                confidence = 1.0,
                source = "explicit",
                appBarTitle = extractToolbarTitle(activity)
            )
        }

        // Auto-derive from class name
        val targetClass = topFragment?.javaClass?.simpleName ?: activity.javaClass.simpleName
        val screenKey = deriveScreenKey(targetClass)
        val title = activity.title?.toString() ?: deriveTitle(targetClass)

        return ScreenInfo(
            screenKey = screenKey,
            screenTitle = title,
            frameworkType = detectFrameworkType(activity),
            activityChain = buildActivityChain(activity, topFragment),
            activeTab = detectActiveTab(activity),
            navigationDepth = getNavigationDepth(activity),
            presentedModals = emptyList(),
            confidence = 0.8,
            source = "derived",
            appBarTitle = extractToolbarTitle(activity)
        )
    }

    private fun findTopFragment(activity: Activity): Fragment? {
        if (activity !is AppCompatActivity) return null
        val fragments = activity.supportFragmentManager.fragments
        return fragments.lastOrNull { it.isVisible }
    }

    private fun buildActivityChain(activity: Activity, topFragment: Fragment?): List<String> {
        val chain = mutableListOf(activity.javaClass.simpleName)
        if (activity is AppCompatActivity) {
            val backStackCount = activity.supportFragmentManager.backStackEntryCount
            for (i in 0 until backStackCount) {
                val entry = activity.supportFragmentManager.getBackStackEntryAt(i)
                chain.add(entry.name ?: "Fragment#$i")
            }
        }
        if (topFragment != null) {
            val name = topFragment.javaClass.simpleName
            if (!chain.contains(name)) {
                chain.add(name)
            }
        }
        return chain
    }

    private fun detectActiveTab(activity: Activity): String? {
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

    private fun getNavigationDepth(activity: Activity): Int {
        if (activity !is AppCompatActivity) return 0
        return activity.supportFragmentManager.backStackEntryCount
    }

    private fun detectFrameworkType(activity: Activity): String {
        val className = activity.javaClass.name
        if (className.contains("ComponentActivity") || className.contains("ComposeActivity")) {
            return "compose"
        }
        return "android"
    }

    private fun extractToolbarTitle(activity: Activity): String? {
        val decorView = activity.window?.decorView ?: return null
        val toolbar = findViewOfType(decorView, Toolbar::class.java)
        if (toolbar?.title != null) return toolbar.title.toString()
        if (activity is AppCompatActivity) {
            val actionBarTitle = activity.supportActionBar?.title?.toString()
            if (!actionBarTitle.isNullOrEmpty()) return actionBarTitle
        }
        return activity.actionBar?.title?.toString()
    }

    private fun <T : View> findViewOfType(root: View, clazz: Class<T>): T? {
        if (clazz.isInstance(root)) return clazz.cast(root)
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findViewOfType(root.getChildAt(i), clazz)
                if (found != null) return found
            }
        }
        return null
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
