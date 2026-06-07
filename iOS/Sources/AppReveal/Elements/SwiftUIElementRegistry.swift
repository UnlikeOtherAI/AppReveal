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

#if os(iOS)

import UIKit
import SwiftUI

#if DEBUG

@MainActor
final class SwiftUIElementRegistry {

    static let shared = SwiftUIElementRegistry()

    private struct Entry {
        let frame: CGRect
        let label: String?
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    func register(id: String, frame: CGRect, label: String?) {
        entries[id] = Entry(frame: frame, label: label)
    }

    func unregister(id: String) {
        entries.removeValue(forKey: id)
    }

    func currentElements() -> [(id: String, frame: CGRect, label: String?)] {
        entries.map { (id: $0.key, frame: $0.value.frame, label: $0.value.label) }
    }

    func findElement(byId id: String) -> (id: String, frame: CGRect, label: String?)? {
        guard let entry = entries[id] else { return nil }
        return (id: id, frame: entry.frame, label: entry.label)
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
                        label: registeredLabel
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
    /// SwiftUI defers building its accessibility tree until VoiceOver is active, so
    /// AppReveal's in-process scan cannot find these elements automatically.
    ///
    /// Usage:
    /// ```swift
    /// Button(action: send) {
    ///     Image(systemName: "arrow.up.circle.fill")
    /// }
    /// #if DEBUG
    /// .appReveal("chat.send_button", label: "Send")
    /// #endif
    /// ```
    ///
    /// - Parameters:
    ///   - id: Stable dot-namespaced identifier (e.g. `"chat.send_button"`).
    ///   - label: Optional human-readable label for the element.
    func appReveal(_ id: String, label: String? = nil) -> some View {
        modifier(AppRevealModifier(id: id, label: label))
    }
}

#endif

#endif
