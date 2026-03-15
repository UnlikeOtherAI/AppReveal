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

    func resolve() -> ScreenInfo {
        let topVC = findTopViewController()
        let chain = buildControllerChain(from: topVC)
        let tab = findActiveTab()
        let modals = findPresentedModals()
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

        // Fallback: use class name
        let className = topVC.map { String(describing: type(of: $0)) } ?? "unknown"
        return ScreenInfo(
            screenKey: className,
            screenTitle: topVC?.title ?? className,
            frameworkType: detectFrameworkType(topVC),
            controllerChain: chain,
            activeTab: tab,
            navigationDepth: navDepth,
            presentedModals: modals,
            confidence: 0.3
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

    private func detectFrameworkType(_ vc: UIViewController?) -> String {
        guard let vc = vc else { return "unknown" }
        let typeName = String(describing: type(of: vc))
        if typeName.contains("HostingController") { return "swiftui" }
        return "uikit"
    }
}

#endif
