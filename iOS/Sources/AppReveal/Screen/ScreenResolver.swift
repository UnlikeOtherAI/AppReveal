// Resolves the currently active screen

import Foundation
import UIKit

#if DEBUG

@MainActor
final class ScreenResolver {

    static let shared = ScreenResolver()

    private var registeredScreens: [ObjectIdentifier: ScreenIdentifiable] = [:]

    private init() {}

    func register(_ screen: ScreenIdentifiable) {
        registeredScreens[ObjectIdentifier(screen)] = screen
    }

    func unregister(_ screen: ScreenIdentifiable) {
        registeredScreens.removeValue(forKey: ObjectIdentifier(screen))
    }

    func resolve(windowId: String? = nil) -> ScreenInfo {
        let topVC = findTopViewController(windowId: windowId)
        let chain = buildControllerChain(from: topVC)
        let tab = findActiveTab(windowId: windowId)
        let modals = findPresentedModals(windowId: windowId)
        let navDepth = findNavigationDepth(from: topVC)

        // Check if top VC conforms to ScreenIdentifiable
        if let identifiable = topVC as? ScreenIdentifiable {
            return ScreenInfo(
                screenKey: identifiable.screenKey,
                screenTitle: identifiable.screenTitle,
                frameworkType: detectFrameworkType(topVC),
                controllerChain: chain,
                activeTab: tab,
                navigationDepth: navDepth,
                presentedModals: modals,
                confidence: 1.0
            )
        }

        // Auto-derive from class name — no protocol needed
        let className = topVC.map { String(describing: type(of: $0)) } ?? "unknown"
        let screenKey = Self.deriveScreenKey(from: className)
        let title = topVC?.title ?? topVC?.navigationItem.title ?? Self.deriveTitle(from: className)
        return ScreenInfo(
            screenKey: screenKey,
            screenTitle: title,
            frameworkType: detectFrameworkType(topVC),
            controllerChain: chain,
            activeTab: tab,
            navigationDepth: navDepth,
            presentedModals: modals,
            confidence: 0.8
        )
    }

    // MARK: - UIKit hierarchy

    private func findTopViewController(windowId: String? = nil) -> UIViewController? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let rootVC = ref.rootViewController else {
            return nil
        }
        return topMost(from: rootVC)
    }

    private func topMost(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        return vc
    }

    private func buildControllerChain(from vc: UIViewController?) -> [String] {
        var chain: [String] = []
        var current = vc
        while let c = current {
            chain.insert(String(describing: type(of: c)), at: 0)
            current = c.parent
        }
        return chain
    }

    private func findActiveTab(windowId: String? = nil) -> String? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let root = ref.rootViewController else { return nil }

        if let tab = root as? UITabBarController {
            return tab.selectedViewController.map { String(describing: type(of: $0)) }
        }
        return nil
    }

    private func findPresentedModals(windowId: String? = nil) -> [String] {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              var vc = ref.rootViewController else { return [] }

        var modals: [String] = []
        while let presented = vc.presentedViewController {
            modals.append(String(describing: type(of: presented)))
            vc = presented
        }
        return modals
    }

    private func findNavigationDepth(from vc: UIViewController?) -> Int {
        vc?.navigationController?.viewControllers.count ?? 0
    }

    private func detectFrameworkType(_ vc: UIViewController?) -> String {
        guard let vc = vc else { return "unknown" }
        let typeName = String(describing: type(of: vc))
        if typeName.contains("HostingController") { return "swiftui" }
        return "uikit"
    }

    // MARK: - Auto-derivation

    /// "OrderDetailViewController" -> "orders.detail"
    /// "LoginViewController" -> "login"
    /// "ProductListVC" -> "product.list"
    static func deriveScreenKey(from className: String) -> String {
        var name = className
        // Strip common suffixes
        for suffix in ["ViewController", "Controller", "Screen", "View", "VC"] {
            if name.hasSuffix(suffix) && name.count > suffix.count {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        // Split on camelCase boundaries
        let parts = splitCamelCase(name)
        return parts.joined(separator: ".").lowercased()
    }

    /// "OrderDetailViewController" -> "Order Detail"
    static func deriveTitle(from className: String) -> String {
        var name = className
        for suffix in ["ViewController", "Controller", "Screen", "View", "VC"] {
            if name.hasSuffix(suffix) && name.count > suffix.count {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        let parts = splitCamelCase(name)
        return parts.joined(separator: " ")
    }

    private static func splitCamelCase(_ string: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for char in string {
            if char.isUppercase && !current.isEmpty {
                parts.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

#endif
