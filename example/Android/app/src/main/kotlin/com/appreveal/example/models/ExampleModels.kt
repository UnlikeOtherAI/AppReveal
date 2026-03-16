package com.appreveal.example.models

import java.util.Date

data class ExampleOrder(
    val id: String,
    val status: String,
    val total: Double,
    val items: List<OrderItem>,
    val createdAt: Date
) {
    data class OrderItem(
        val name: String,
        val quantity: Int,
        val price: Double
    )

    companion object {
        val samples: List<ExampleOrder> = listOf(
            ExampleOrder(
                id = "ORD-001",
                status = "Shipped",
                total = 89.99,
                items = listOf(
                    OrderItem("Wireless Headphones", 1, 59.99),
                    OrderItem("USB-C Cable", 2, 15.00)
                ),
                createdAt = Date(System.currentTimeMillis() - 86400000L * 2)
            ),
            ExampleOrder(
                id = "ORD-002",
                status = "Pending",
                total = 249.00,
                items = listOf(
                    OrderItem("Mechanical Keyboard", 1, 199.00),
                    OrderItem("Wrist Rest", 1, 50.00)
                ),
                createdAt = Date(System.currentTimeMillis() - 86400000L)
            ),
            ExampleOrder(
                id = "ORD-003",
                status = "Delivered",
                total = 34.50,
                items = listOf(
                    OrderItem("Phone Case", 1, 24.50),
                    OrderItem("Screen Protector", 1, 10.00)
                ),
                createdAt = Date(System.currentTimeMillis() - 86400000L * 7)
            ),
            ExampleOrder(
                id = "ORD-004",
                status = "Shipped",
                total = 149.99,
                items = listOf(
                    OrderItem("Bluetooth Speaker", 1, 149.99)
                ),
                createdAt = Date(System.currentTimeMillis() - 86400000L * 3)
            ),
            ExampleOrder(
                id = "ORD-005",
                status = "Pending",
                total = 67.00,
                items = listOf(
                    OrderItem("Notebook Stand", 1, 45.00),
                    OrderItem("Mouse Pad", 1, 22.00)
                ),
                createdAt = Date(System.currentTimeMillis() - 3600000L)
            )
        )
    }
}

data class ExampleProduct(
    val id: String,
    val name: String,
    val description: String,
    val price: Double,
    val iconResName: String,
    val category: String
) {
    companion object {
        val samples: List<ExampleProduct> = listOf(
            ExampleProduct(
                id = "PROD-001", name = "Wireless Headphones",
                description = "Premium noise-canceling wireless headphones with 30-hour battery life.",
                price = 59.99, iconResName = "ic_menu_compass", category = "Audio"
            ),
            ExampleProduct(
                id = "PROD-002", name = "Mechanical Keyboard",
                description = "Full-size mechanical keyboard with Cherry MX switches and RGB backlighting.",
                price = 199.00, iconResName = "ic_menu_edit", category = "Input"
            ),
            ExampleProduct(
                id = "PROD-003", name = "Bluetooth Speaker",
                description = "Portable waterproof speaker with 360-degree sound.",
                price = 149.99, iconResName = "ic_lock_idle_alarm", category = "Audio"
            ),
            ExampleProduct(
                id = "PROD-004", name = "USB-C Hub",
                description = "7-in-1 USB-C hub with HDMI, SD card, and USB-A ports.",
                price = 45.00, iconResName = "ic_menu_share", category = "Accessories"
            ),
            ExampleProduct(
                id = "PROD-005", name = "Webcam HD",
                description = "1080p webcam with built-in microphone and auto-focus.",
                price = 79.99, iconResName = "ic_menu_camera", category = "Video"
            ),
            ExampleProduct(
                id = "PROD-006", name = "Laptop Stand",
                description = "Adjustable aluminum laptop stand with cable management.",
                price = 55.00, iconResName = "ic_menu_slideshow", category = "Accessories"
            ),
            ExampleProduct(
                id = "PROD-007", name = "Wireless Mouse",
                description = "Ergonomic wireless mouse with adjustable DPI.",
                price = 35.00, iconResName = "ic_menu_manage", category = "Input"
            ),
            ExampleProduct(
                id = "PROD-008", name = "Monitor Light Bar",
                description = "LED monitor light bar with adjustable color temperature.",
                price = 42.00, iconResName = "ic_menu_view", category = "Lighting"
            )
        )
    }
}
