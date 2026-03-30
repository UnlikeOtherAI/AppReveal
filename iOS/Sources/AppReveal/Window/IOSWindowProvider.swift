// iOS window provider -- iterates all connected scenes and windows

#if os(iOS)

import UIKit

#if DEBUG

@MainActor
final class IOSWindowProvider: WindowProvider {

    static let shared = IOSWindowProvider()

    private init() {}

    func allWindows() -> [WindowRef] {
        let keyWin = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { $0.keyWindow }
            .first

        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { !$0.isHidden }
            .map { window in
                WindowRef(
                    id: windowId(for: window),
                    title: windowTitle(for: window),
                    frame: window.frame,
                    isKey: window === keyWin,
                    nativeWindow: window
                )
            }
    }

    func keyWindow() -> WindowRef? {
        allWindows().first(where: \.isKey)
    }

    func window(id: String) -> WindowRef? {
        allWindows().first { $0.id == id }
    }

    // MARK: - Private

    private func windowId(for window: UIWindow) -> String {
        if let identifier = window.accessibilityIdentifier, !identifier.isEmpty {
            return identifier
        }
        return "window-\(ObjectIdentifier(window).hashValue)"
    }

    private func windowTitle(for window: UIWindow) -> String {
        if let scene = window.windowScene {
            return scene.title.isEmpty
                ? (scene.session.configuration.name ?? "Window")
                : scene.title
        }
        return "Window"
    }
}

#endif

#endif
