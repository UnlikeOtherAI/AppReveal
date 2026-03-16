package com.appreveal.example.navigation

import com.appreveal.state.NavigationProviding

object ExampleRouter : NavigationProviding {

    override var currentRoute: String = "orders.list"
        private set

    private val routeStack: MutableList<String> = mutableListOf("orders.list")
    private val modalStackInternal: MutableList<String> = mutableListOf()

    fun push(route: String) {
        routeStack.add(route)
        currentRoute = route
    }

    fun pop() {
        if (routeStack.size > 1) {
            routeStack.removeLast()
            currentRoute = routeStack.lastOrNull() ?: "unknown"
        }
    }

    fun presentModal(route: String) {
        modalStackInternal.add(route)
    }

    fun dismissModal() {
        if (modalStackInternal.isNotEmpty()) {
            modalStackInternal.removeLast()
        }
    }

    override val navigationStack: List<String> get() = routeStack.toList()
    override val presentedModals: List<String> get() = modalStackInternal.toList()
}
