// macOS window provider -- iterates all NSApplication windows

import Foundation

#if DEBUG
#if os(macOS)

import AppKit

@MainActor
final class MacOSWindowProvider: WindowProvider {

    static let shared = MacOSWindowProvider()

    private init() {}

    func allWindows() -> [WindowRef] {
        NSApplication.shared.windows
            .filter { $0.isVisible }
            .map { window in
                WindowRef(
                    id: (window.identifier?.rawValue)
                        ?? "window_\(window.windowNumber)",
                    title: window.title,
                    frame: window.frame,
                    isKey: window.isKeyWindow,
                    nativeWindow: window
                )
            }
    }

    func keyWindow() -> WindowRef? {
        allWindows().first { $0.isKey } ?? allWindows().first
    }

    func window(id: String) -> WindowRef? {
        allWindows().first { $0.id == id }
    }
}

#endif // os(macOS)
#endif // DEBUG
