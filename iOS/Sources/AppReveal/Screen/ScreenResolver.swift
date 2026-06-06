// Resolves the currently active screen

import Foundation

#if DEBUG

// MARK: - Cross-platform screen key derivation

/// Utility for deriving screen keys and titles from class names.
/// Used by both iOS and macOS ScreenResolver implementations.
enum ScreenKeyDerivation {

    /// "OrderDetailViewController" -> "orders.detail"
    /// "LoginViewController" -> "login"
    /// "ProductListVC" -> "product.list"
    static func deriveScreenKey(from className: String) -> String {
        var name = className
        // Strip common suffixes
        for suffix in ["ViewController", "Controller", "Screen", "View", "VC", "WindowController"] {
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
        for suffix in ["ViewController", "Controller", "Screen", "View", "VC", "WindowController"] {
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

// MARK: - iOS ScreenResolver

#if os(iOS)

import UIKit

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

        let navBarTitle = extractNavBarTitle(windowId: windowId)

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
                confidence: 1.0,
                source: "explicit",
                appBarTitle: navBarTitle
            )
        }

        // Auto-derive from class name -- no protocol needed
        let className = topVC.map { String(describing: type(of: $0)) } ?? "unknown"
        let screenKey = Self.deriveScreenKey(from: className)
        let title = topVC?.title ?? topVC?.navigationItem.title ?? navBarTitle ?? Self.deriveTitle(from: className)
        return ScreenInfo(
            screenKey: screenKey,
            screenTitle: title,
            frameworkType: detectFrameworkType(topVC),
            controllerChain: chain,
            activeTab: tab,
            navigationDepth: navDepth,
            presentedModals: modals,
            confidence: navBarTitle != nil ? 0.6 : 0.8,
            source: "derived",
            appBarTitle: navBarTitle
        )
    }

    // Delegate to shared derivation logic
    static func deriveScreenKey(from className: String) -> String {
        ScreenKeyDerivation.deriveScreenKey(from: className)
    }

    static func deriveTitle(from className: String) -> String {
        ScreenKeyDerivation.deriveTitle(from: className)
    }

    // MARK: - UIKit hierarchy

    private func findTopViewController(windowId: String? = nil) -> UIViewController? {
        guard let rootVC = contentWindowRoots(windowId: windowId).first else {
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
        guard let root = contentWindowRoots(windowId: windowId).last else { return nil }

        if let tab = root as? UITabBarController {
            return tab.selectedViewController.map { String(describing: type(of: $0)) }
        }
        return nil
    }

    private func findPresentedModals(windowId: String? = nil) -> [String] {
        let roots = contentWindowRoots(windowId: windowId)
        guard var vc = roots.last else { return [] }

        var modals: [String] = []
        while let presented = vc.presentedViewController {
            modals.append(String(describing: type(of: presented)))
            vc = presented
        }

        if !modals.isEmpty {
            return modals
        }

        let overlayWindowModals = roots.dropLast().map { String(describing: type(of: topMost(from: $0))) }
        if !overlayWindowModals.isEmpty {
            return Array(NSOrderedSet(array: overlayWindowModals)) as? [String] ?? overlayWindowModals
        }

        let fallbackModals = roots.flatMap(findVisiblePresentedControllers(from:))
            .map { String(describing: type(of: $0)) }
        return Array(NSOrderedSet(array: fallbackModals)) as? [String] ?? fallbackModals
    }

    private func contentWindowRoots(windowId: String? = nil) -> [UIViewController] {
        IOSWindowProvider.shared.windowsForInteraction(windowId: windowId)
            .compactMap(\.rootViewController)
            .filter { !isKeyboardController($0) }
    }

    private func isKeyboardController(_ controller: UIViewController) -> Bool {
        String(describing: type(of: controller)).contains("UIInputWindowController")
    }

    private func findVisiblePresentedControllers(from root: UIViewController) -> [UIViewController] {

        var results: [UIViewController] = []
        var visited: Set<ObjectIdentifier> = []

        func walk(_ vc: UIViewController) {
            let identifier = ObjectIdentifier(vc)
            guard visited.insert(identifier).inserted else { return }

            if vc !== root,
               vc.viewIfLoaded?.window != nil,
               vc.presentingViewController != nil || vc.presentationController?.presentingViewController != nil {
                results.append(vc)
            }

            if let presented = vc.presentedViewController {
                walk(presented)
            }
            if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
                walk(visible)
            }
            if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
                walk(selected)
            }
            for child in vc.children {
                walk(child)
            }
        }

        walk(root)
        return results
    }

    private func findNavigationDepth(from vc: UIViewController?) -> Int {
        vc?.navigationController?.viewControllers.count ?? 0
    }

    private func extractNavBarTitle(windowId: String? = nil) -> String? {
        for root in contentWindowRoots(windowId: windowId) {
            if let title = findNavBarTitle(in: root.view) {
                return title
            }
        }
        return nil
    }

    private func findNavBarTitle(in view: UIView) -> String? {
        if let navBar = view as? UINavigationBar {
            return navBar.topItem?.title
        }
        for subview in view.subviews {
            if let title = findNavBarTitle(in: subview) {
                return title
            }
        }
        return nil
    }

    private func detectFrameworkType(_ vc: UIViewController?) -> String {
        guard let vc = vc else { return "unknown" }
        let typeName = String(describing: type(of: vc))
        if typeName.contains("HostingController") { return "swiftui" }
        return "uikit"
    }
}

#endif // os(iOS)

#endif // DEBUG
