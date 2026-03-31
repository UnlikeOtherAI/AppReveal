// Resolves the currently active screen.
// JS can provide a screen key via setJSScreen(key:title:confidence:) which takes
// priority over UIViewController auto-detection.

import Foundation
import UIKit

@MainActor
final class ScreenResolver {

    static let shared = ScreenResolver()

    // JS-provided screen override
    private var jsScreenKey: String?
    private var jsScreenTitle: String?
    private var jsConfidence: Double = 1.0

    private init() {}

    // MARK: - JS screen override

    func setJSScreen(key: String, title: String, confidence: Double) {
        jsScreenKey = key
        jsScreenTitle = title
        jsConfidence = confidence
    }

    func clearJSScreen() {
        jsScreenKey = nil
        jsScreenTitle = nil
        jsConfidence = 1.0
    }

    // MARK: - Resolution

    func resolve() -> ScreenInfo {
        let topVC = findTopViewController()
        let chain = buildControllerChain(from: topVC)
        let tab = findActiveTab()
        let modals = findPresentedModals()
        let navDepth = findNavigationDepth(from: topVC)
        let navBarTitle = extractNavBarTitle()

        // If JS has provided a screen key, use it with high confidence
        if let jsKey = jsScreenKey, let jsTitle = jsScreenTitle {
            return ScreenInfo(
                screenKey: jsKey,
                screenTitle: jsTitle,
                frameworkType: detectFrameworkType(topVC),
                controllerChain: chain,
                activeTab: tab,
                navigationDepth: navDepth,
                presentedModals: modals,
                confidence: jsConfidence,
                source: "explicit",
                appBarTitle: navBarTitle
            )
        }

        // Check if top VC conforms to ScreenIdentifiable (if app has adopted the protocol)
        // In the RN module we don't expose that protocol publicly, so this is a fallback hook.

        // Auto-derive from class name
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

    // MARK: - UIKit hierarchy

    private func findTopViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.keyWindow?.rootViewController else {
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

    private func findActiveTab() -> String? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return nil }

        if let tab = root as? UITabBarController {
            return tab.selectedViewController.map { String(describing: type(of: $0)) }
        }
        return nil
    }

    private func findPresentedModals() -> [String] {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              var vc = scene.keyWindow?.rootViewController else { return [] }

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

    private func extractNavBarTitle() -> String? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else { return nil }
        return findNavBarTitle(in: window)
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

    // MARK: - Auto-derivation

    /// "OrderDetailViewController" -> "orders.detail"
    static func deriveScreenKey(from className: String) -> String {
        var name = className
        for suffix in ["ViewController", "Controller", "Screen", "View", "VC"] {
            if name.hasSuffix(suffix) && name.count > suffix.count {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
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
