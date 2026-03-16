package com.appreveal.example

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.navigation.NavController
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.NavigationUI
import com.appreveal.example.navigation.ExampleRouter
import com.appreveal.example.screens.LoginActivity
import com.appreveal.example.services.ExampleStateContainer
import com.google.android.material.bottomnavigation.BottomNavigationView

class MainActivity : AppCompatActivity() {

    private lateinit var navController: NavController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val navHostFragment = supportFragmentManager
            .findFragmentById(R.id.navHostFragment) as NavHostFragment
        navController = navHostFragment.navController

        val bottomNav = findViewById<BottomNavigationView>(R.id.bottomNav)
        NavigationUI.setupWithNavController(bottomNav, navController)

        bottomNav.setOnItemSelectedListener { item ->
            val tabIndex = when (item.itemId) {
                R.id.navigation_orders -> 0
                R.id.navigation_catalog -> 1
                R.id.navigation_profile -> 2
                R.id.navigation_settings -> 3
                R.id.navigation_web -> 4
                else -> 0
            }
            ExampleStateContainer.selectedTab = tabIndex
            NavigationUI.onNavDestinationSelected(item, navController)
            true
        }

        // Show login on first launch
        if (!ExampleStateContainer.isLoggedIn) {
            startActivity(Intent(this, LoginActivity::class.java))
        }

        handleDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        intent?.let { handleDeepLink(it) }
    }

    private fun handleDeepLink(intent: Intent) {
        val uri = intent.data ?: return
        val host = uri.host ?: return
        val bottomNav = findViewById<BottomNavigationView>(R.id.bottomNav)

        when (host) {
            "orders" -> {
                bottomNav.selectedItemId = R.id.navigation_orders
                val orderId = uri.pathSegments.firstOrNull()
                if (orderId != null) {
                    val bundle = Bundle().apply { putString("orderId", orderId) }
                    navController.navigate(R.id.orderDetailFragment, bundle)
                }
            }
            "catalog" -> bottomNav.selectedItemId = R.id.navigation_catalog
            "profile" -> bottomNav.selectedItemId = R.id.navigation_profile
            "settings" -> bottomNav.selectedItemId = R.id.navigation_settings
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        return navController.navigateUp() || super.onSupportNavigateUp()
    }
}
