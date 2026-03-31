// Protocol for platform-specific window enumeration

import Foundation

#if DEBUG

/// Provides access to all application windows across scenes.
@MainActor
public protocol WindowProvider {
    /// All visible windows across every connected scene.
    func allWindows() -> [WindowRef]

    /// The current key window, if any.
    func keyWindow() -> WindowRef?

    /// Look up a window by its identifier.
    func window(id: String) -> WindowRef?
}

extension WindowProvider {
    /// Resolve a window by optional ID, falling back to the key window.
    public func resolve(windowId: String?) -> WindowRef? {
        if let windowId {
            return window(id: windowId)
        }
        return keyWindow()
    }
}

// MARK: - Global accessor

/// The platform-appropriate window provider singleton.
@MainActor
public var platformWindowProvider: WindowProvider {
    #if os(iOS)
    IOSWindowProvider.shared
    #elseif os(macOS)
    MacOSWindowProvider.shared
    #endif
}

#endif
