// macOS screen resolver -- walks NSViewController hierarchy

import Foundation

#if DEBUG
#if os(macOS)

import AppKit

@MainActor
final class MacOSScreenResolver {

    static let shared = MacOSScreenResolver()

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

        let windowTitle = platformWindowProvider.resolve(windowId: windowId)?.nativeWindow.title

        if let identifiable = registeredScreen(for: topVC) ?? (topVC as? ScreenIdentifiable) {
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
                appBarTitle: windowTitle
            )
        }

        let className = topVC.map { String(describing: type(of: $0)) } ?? "unknown"
        let screenKey = ScreenKeyDerivation.deriveScreenKey(from: className)
        let title = topVC?.title ?? windowTitle ?? ScreenKeyDerivation.deriveTitle(from: className)
        return ScreenInfo(
            screenKey: screenKey,
            screenTitle: title,
            frameworkType: detectFrameworkType(topVC),
            controllerChain: chain,
            activeTab: tab,
            navigationDepth: navDepth,
            presentedModals: modals,
            confidence: 0.8,
            source: "derived",
            appBarTitle: windowTitle
        )
    }

    private func findTopViewController(windowId: String? = nil) -> NSViewController? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return nil
        }

        if let sheetController = ref.nativeWindow.attachedSheet?.contentViewController {
            return topMost(from: sheetController)
        }

        guard let rootVC = ref.rootViewController else {
            return nil
        }

        return topMost(from: rootVC)
    }

    private func topMost(from vc: NSViewController) -> NSViewController {
        if let presented = vc.presentedViewControllers?.last {
            return topMost(from: presented)
        }

        if let tab = vc as? NSTabViewController,
           let selected = selectedChild(in: tab) {
            return topMost(from: selected)
        }

        if let split = vc as? NSSplitViewController,
           let detail = split.children.last {
            return topMost(from: detail)
        }

        if let child = vc.children.last {
            return topMost(from: child)
        }

        return vc
    }

    private func buildControllerChain(from vc: NSViewController?) -> [String] {
        var chain: [String] = []
        var current = vc
        while let controller = current {
            chain.insert(String(describing: type(of: controller)), at: 0)
            current = controller.parent
        }
        return chain
    }

    private func findActiveTab(windowId: String? = nil) -> String? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let root = ref.rootViewController else {
            return nil
        }

        return findActiveTab(in: root)
    }

    private func findPresentedModals(windowId: String? = nil) -> [String] {
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return []
        }

        var modals: [String] = []

        if let sheetController = ref.nativeWindow.attachedSheet?.contentViewController {
            modals.append(String(describing: type(of: sheetController)))
            modals.append(contentsOf: presentedControllers(startingAt: sheetController))
        }

        guard let root = ref.rootViewController else {
            return modals
        }

        for presented in root.presentedViewControllers ?? [] {
            modals.append(String(describing: type(of: presented)))
            modals.append(contentsOf: presentedControllers(startingAt: presented))
        }

        return modals
    }

    private func findNavigationDepth(from vc: NSViewController?) -> Int {
        guard let vc else { return 0 }

        var depth = 0
        var current: NSViewController? = vc
        while let parent = current?.parent {
            depth += 1
            current = parent
        }
        return depth
    }

    private func detectFrameworkType(_ vc: NSViewController?) -> String {
        guard let vc else { return "unknown" }

        let typeName = String(describing: type(of: vc))
        if typeName.contains("NSHostingController") || typeName.contains("HostingController") {
            return "swiftui"
        }
        return "appkit"
    }

    private func selectedChild(in tab: NSTabViewController) -> NSViewController? {
        let index = tab.selectedTabViewItemIndex
        guard index >= 0, index < tab.children.count else {
            return nil
        }
        return tab.children[index]
    }

    private func findActiveTab(in vc: NSViewController) -> String? {
        if let tab = vc as? NSTabViewController,
           let selected = selectedChild(in: tab) {
            return String(describing: type(of: selected))
        }

        for presented in vc.presentedViewControllers ?? [] {
            if let activeTab = findActiveTab(in: presented) {
                return activeTab
            }
        }

        for child in vc.children {
            if let activeTab = findActiveTab(in: child) {
                return activeTab
            }
        }

        return nil
    }

    private func presentedControllers(startingAt vc: NSViewController) -> [String] {
        var controllers: [String] = []
        for presented in vc.presentedViewControllers ?? [] {
            controllers.append(String(describing: type(of: presented)))
            controllers.append(contentsOf: presentedControllers(startingAt: presented))
        }
        return controllers
    }

    private func registeredScreen(for vc: NSViewController?) -> ScreenIdentifiable? {
        guard let vc else { return nil }

        if let registered = registeredScreens[ObjectIdentifier(vc)] {
            return registered
        }

        var current = vc.parent
        while let parent = current {
            if let registered = registeredScreens[ObjectIdentifier(parent)] {
                return registered
            }
            current = parent.parent
        }

        return nil
    }
}

#endif // os(macOS)
#endif // DEBUG
