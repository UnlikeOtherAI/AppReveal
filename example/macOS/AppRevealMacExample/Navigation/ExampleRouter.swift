import Foundation

#if DEBUG
import AppReveal
#endif

final class ExampleRouter {

    static let shared = ExampleRouter()

    private(set) var currentRoute = ExampleSection.orders.rootRoute
    private(set) var routeStack: [String] = [ExampleSection.orders.rootRoute]
    private(set) var modalStack: [String] = []

    private init() {}

    func switchSection(_ section: ExampleSection) {
        ExampleStateContainer.shared.selectedSection = section
        currentRoute = section.rootRoute
        routeStack = [section.rootRoute]
    }

    func showOrderDetail(_ order: ExampleOrder) {
        currentRoute = "orders.detail"
        routeStack = [ExampleSection.orders.rootRoute, "orders.detail.\(order.id)"]
    }

    func showProductDetail(_ product: ExampleProduct) {
        currentRoute = "catalog.detail"
        routeStack = [ExampleSection.catalog.rootRoute, "catalog.detail.\(product.id)"]
    }

    func presentModal(route: String) {
        modalStack.append(route)
    }

    func dismissModal(route: String) {
        modalStack.removeAll { $0 == route }
    }
}

#if DEBUG
extension ExampleRouter: NavigationProviding {
    var navigationStack: [String] { routeStack }
    var presentedModals: [String] { modalStack }
}
#endif
