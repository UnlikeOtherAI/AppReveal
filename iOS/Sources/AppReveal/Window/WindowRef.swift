// Platform-agnostic window reference for multi-window support

import Foundation

#if DEBUG

#if os(iOS)
import UIKit
public typealias NativeWindow = UIWindow
public typealias NativeView = UIView
public typealias NativeViewController = UIViewController
#elseif os(macOS)
import AppKit
public typealias NativeWindow = NSWindow
public typealias NativeView = NSView
public typealias NativeViewController = NSViewController
#endif

/// A lightweight reference to a native window with metadata.
public struct WindowRef {
    public let id: String
    public let title: String
    public let frame: CGRect
    public let isKey: Bool
    public let nativeWindow: NativeWindow
}

// MARK: - Platform convenience accessors

#if os(iOS)
extension WindowRef {
    /// The root view controller of the referenced window.
    public var rootViewController: UIViewController? {
        nativeWindow.rootViewController
    }
}
#elseif os(macOS)
extension WindowRef {
    /// The content view of the referenced window.
    public var contentView: NSView? {
        nativeWindow.contentView
    }

    /// The content view controller of the referenced window.
    public var rootViewController: NSViewController? {
        nativeWindow.contentViewController
    }
}
#endif

#endif
