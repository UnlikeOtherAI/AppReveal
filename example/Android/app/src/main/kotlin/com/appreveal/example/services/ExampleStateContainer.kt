package com.appreveal.example.services

import com.appreveal.state.StateProviding

object ExampleStateContainer : StateProviding {

    var isLoggedIn: Boolean = false
    var userEmail: String = ""
    var userName: String = "Test User"
    var selectedTab: Int = 0
    var cartItemCount: Int = 2
    var lastSyncDate: String = java.text.SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        java.util.Locale.US
    ).format(java.util.Date())

    override fun snapshot(): Map<String, Any?> = mapOf(
        "isLoggedIn" to isLoggedIn,
        "userEmail" to userEmail,
        "userName" to userName,
        "selectedTab" to selectedTab,
        "cartItemCount" to cartItemCount,
        "lastSyncDate" to lastSyncDate
    )
}
