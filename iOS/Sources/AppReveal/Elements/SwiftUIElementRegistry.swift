// SwiftUI opt-in element registration for iOS 26+
//
// On iOS 26, _UIHostingView returns an empty accessibilityElements array and
// accessibilityElementCount() == 0 when VoiceOver is off. SwiftUI defers
// building its accessibility tree to when a real assistive technology is running.
// AppReveal's in-process query cannot trigger that build without VoiceOver.
//
// Solution: apps opt in by applying .appReveal("id") to SwiftUI views.
// The modifier tracks the view's global frame via PreferenceKey and registers
// it with SwiftUIElementRegistry, which ElementInventory includes in get_elements.

import Foundation

#if os(iOS) || os(macOS)

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if DEBUG

@MainActor
final class SwiftUIElementRegistry {

    static let shared = SwiftUIElementRegistry()

    private struct Entry {
        let frame: CGRect
        let label: String?
        let windowId: String?
        let activate: (() -> Void)?
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    func register(id: String, frame: CGRect, label: String?, activate: (() -> Void)? = nil) {
        entries[id] = Entry(
            frame: frame,
            label: label,
            windowId: Self.windowId(containing: frame),
            activate: activate
        )
    }

    func unregister(id: String) {
        entries.removeValue(forKey: id)
    }

    func currentElements(windowIds: Set<String>) -> [(id: String, frame: CGRect, label: String?)] {
        entries.compactMap { id, entry in
            guard Self.entry(entry, matchesAnyOf: windowIds) else { return nil }
            return (id: id, frame: entry.frame, label: entry.label)
        }
    }

    func findElement(byId id: String, windowIds: Set<String>) -> (id: String, frame: CGRect, label: String?)? {
        guard let entry = entries[id] else { return nil }
        guard Self.entry(entry, matchesAnyOf: windowIds) else { return nil }
        return (id: id, frame: entry.frame, label: entry.label)
    }

    func matchingElements(text: String, matchMode: String, windowIds: Set<String>) -> [(id: String, frame: CGRect, label: String?)] {
        entries.compactMap { id, entry in
            guard Self.entry(entry, matchesAnyOf: windowIds) else { return nil }
            let candidates = [entry.label, id].compactMap { $0 }
            let matches = candidates.contains { candidate in
                switch matchMode {
                case "contains":
                    return candidate.localizedCaseInsensitiveContains(text)
                default:
                    return candidate.caseInsensitiveCompare(text) == .orderedSame
                }
            }
            return matches ? (id: id, frame: entry.frame, label: entry.label) : nil
        }
    }

    func activate(id: String) -> Bool {
        guard let activate = entries[id]?.activate else {
            return false
        }

        activate()
        return true
    }

    private static func entry(_ entry: Entry, matchesAnyOf windowIds: Set<String>) -> Bool {
        guard !windowIds.isEmpty else { return true }
        guard let windowId = entry.windowId ?? windowId(containing: entry.frame) else { return true }
        return windowIds.contains(windowId)
    }

    private static func windowId(containing frame: CGRect) -> String? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        #if os(iOS)
        return IOSWindowProvider.shared.allWindows().first { ref in
            let windowFrame = ref.nativeWindow.convert(ref.nativeWindow.bounds, to: nil)
            return windowFrame.contains(center) || windowFrame.intersects(frame)
        }?.id
        #elseif os(macOS)
        return MacOSWindowProvider.shared.allWindows().first { ref in
            guard let contentView = ref.contentView else { return false }
            let windowFrame = contentView.convert(contentView.bounds, to: nil)
            return windowFrame.contains(center) || windowFrame.intersects(frame)
        }?.id
        #endif
    }
}

// MARK: - CGRect convenience

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - SwiftUI PreferenceKey

private struct AppRevealFramePreference: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - ViewModifier

struct AppRevealModifier: ViewModifier {
    let id: String
    let label: String?
    let activate: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: AppRevealFramePreference.self,
                            value: geo.frame(in: .global)
                        )
                }
            )
            .onPreferenceChange(AppRevealFramePreference.self) { frame in
                guard !frame.isEmpty else { return }
                let registeredId = id
                let registeredLabel = label
                Task { @MainActor in
                    SwiftUIElementRegistry.shared.register(
                        id: registeredId,
                        frame: frame,
                        label: registeredLabel,
                        activate: activate
                    )
                }
            }
            .onDisappear {
                let registeredId = id
                Task { @MainActor in
                    SwiftUIElementRegistry.shared.unregister(id: registeredId)
                }
            }
    }
}

// MARK: - Public View extension

public extension View {
    /// Register this SwiftUI view as a discoverable AppReveal element.
    ///
    /// Required on iOS 26+ for SwiftUI elements that should appear in `get_elements`.
    /// Also available on macOS for SwiftUI controls that do not expose AppKit views
    /// or accessibility identifiers reliably through the NSView hierarchy.
    /// SwiftUI defers building its accessibility tree until VoiceOver is active, so
    /// AppReveal's in-process scan cannot find these elements automatically.
    ///
    /// Usage:
    /// ```swift
    /// Button(action: send) {
    ///     Image(systemName: "arrow.up.circle.fill")
    /// }
    /// #if DEBUG
    /// .appReveal("chat.send_button", label: "Send", activate: send)
    /// #endif
    /// ```
    ///
    /// - Parameters:
    ///   - id: Stable dot-namespaced identifier (e.g. `"chat.send_button"`).
    ///   - label: Optional human-readable label for the element.
    ///   - activate: Optional direct debug activation closure. Use this for SwiftUI
    ///     controls whose gestures are intercepted by ScrollView/Lazy containers.
    func appReveal(_ id: String, label: String? = nil, activate: (() -> Void)? = nil) -> some View {
        modifier(AppRevealModifier(id: id, label: label, activate: activate))
    }
}

#endif

#endif
