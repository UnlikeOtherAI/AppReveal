import UIKit

#if DEBUG
import AppReveal
#endif

class ExampleRouter: NSObject {

    static let shared = ExampleRouter()

    weak var window: UIWindow?

    private(set) var currentRoute: String = "orders.list"
    private(set) var routeStack: [String] = ["orders.list"]
    private(set) var modalStack: [String] = []

    func push(route: String) {
        routeStack.append(route)
        currentRoute = route
    }

    func pop() {
        if routeStack.count > 1 {
            routeStack.removeLast()
            currentRoute = routeStack.last ?? "unknown"
        }
    }

    func presentModal(route: String) {
        modalStack.append(route)
    }

    func dismissModal() {
        if !modalStack.isEmpty {
            modalStack.removeLast()
        }
    }

    func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        let tabBar = window?.rootViewController as? MainTabBarController

        switch host {
        case "orders":
            tabBar?.selectedIndex = 0
            if let orderId = url.pathComponents.dropFirst().first {
                let detail = OrderDetailViewController(orderId: orderId)
                (tabBar?.selectedViewController as? UINavigationController)?.pushViewController(detail, animated: true)
            }
        case "catalog":
            tabBar?.selectedIndex = 1
        case "profile":
            tabBar?.selectedIndex = 2
        case "settings":
            tabBar?.selectedIndex = 3
        default:
            break
        }
    }
}

// MARK: - NavigationProviding

#if DEBUG
extension ExampleRouter: NavigationProviding {
    var navigationStack: [String] { routeStack }
    var presentedModals: [String] { modalStack }
}
#endif
