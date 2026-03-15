import Foundation

// MARK: - Order

struct ExampleOrder {
    let id: String
    let status: String
    let total: Double
    let items: [OrderItem]
    let createdAt: Date

    struct OrderItem {
        let name: String
        let quantity: Int
        let price: Double
    }

    static let samples: [ExampleOrder] = [
        ExampleOrder(
            id: "ORD-001",
            status: "Shipped",
            total: 89.99,
            items: [
                OrderItem(name: "Wireless Headphones", quantity: 1, price: 59.99),
                OrderItem(name: "USB-C Cable", quantity: 2, price: 15.00),
            ],
            createdAt: Date().addingTimeInterval(-86400 * 2)
        ),
        ExampleOrder(
            id: "ORD-002",
            status: "Pending",
            total: 249.00,
            items: [
                OrderItem(name: "Mechanical Keyboard", quantity: 1, price: 199.00),
                OrderItem(name: "Wrist Rest", quantity: 1, price: 50.00),
            ],
            createdAt: Date().addingTimeInterval(-86400)
        ),
        ExampleOrder(
            id: "ORD-003",
            status: "Delivered",
            total: 34.50,
            items: [
                OrderItem(name: "Phone Case", quantity: 1, price: 24.50),
                OrderItem(name: "Screen Protector", quantity: 1, price: 10.00),
            ],
            createdAt: Date().addingTimeInterval(-86400 * 7)
        ),
        ExampleOrder(
            id: "ORD-004",
            status: "Shipped",
            total: 149.99,
            items: [
                OrderItem(name: "Bluetooth Speaker", quantity: 1, price: 149.99),
            ],
            createdAt: Date().addingTimeInterval(-86400 * 3)
        ),
        ExampleOrder(
            id: "ORD-005",
            status: "Pending",
            total: 67.00,
            items: [
                OrderItem(name: "Notebook Stand", quantity: 1, price: 45.00),
                OrderItem(name: "Mouse Pad", quantity: 1, price: 22.00),
            ],
            createdAt: Date().addingTimeInterval(-3600)
        ),
    ]
}

// MARK: - Product

struct ExampleProduct {
    let id: String
    let name: String
    let description: String
    let price: Double
    let iconName: String
    let category: String

    static let samples: [ExampleProduct] = [
        ExampleProduct(
            id: "PROD-001", name: "Wireless Headphones",
            description: "Premium noise-canceling wireless headphones with 30-hour battery life.",
            price: 59.99, iconName: "headphones", category: "Audio"
        ),
        ExampleProduct(
            id: "PROD-002", name: "Mechanical Keyboard",
            description: "Full-size mechanical keyboard with Cherry MX switches and RGB backlighting.",
            price: 199.00, iconName: "keyboard", category: "Input"
        ),
        ExampleProduct(
            id: "PROD-003", name: "Bluetooth Speaker",
            description: "Portable waterproof speaker with 360-degree sound.",
            price: 149.99, iconName: "hifispeaker", category: "Audio"
        ),
        ExampleProduct(
            id: "PROD-004", name: "USB-C Hub",
            description: "7-in-1 USB-C hub with HDMI, SD card, and USB-A ports.",
            price: 45.00, iconName: "cable.connector.horizontal", category: "Accessories"
        ),
        ExampleProduct(
            id: "PROD-005", name: "Webcam HD",
            description: "1080p webcam with built-in microphone and auto-focus.",
            price: 79.99, iconName: "web.camera", category: "Video"
        ),
        ExampleProduct(
            id: "PROD-006", name: "Laptop Stand",
            description: "Adjustable aluminum laptop stand with cable management.",
            price: 55.00, iconName: "laptopcomputer", category: "Accessories"
        ),
        ExampleProduct(
            id: "PROD-007", name: "Wireless Mouse",
            description: "Ergonomic wireless mouse with adjustable DPI.",
            price: 35.00, iconName: "computermouse", category: "Input"
        ),
        ExampleProduct(
            id: "PROD-008", name: "Monitor Light Bar",
            description: "LED monitor light bar with adjustable color temperature.",
            price: 42.00, iconName: "light.max", category: "Lighting"
        ),
    ]
}
