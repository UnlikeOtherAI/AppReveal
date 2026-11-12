// SwiftUI opt-in element registration for iOS 26+
//
// On iOS 26, _UIHostingView returns an empty accessibilityElements array and
// accessibilityElementCount() == 0 when VoiceOver is off. SwiftUI defers
// building its accessibility tree to when a real assistive technology is running.
// AppReveal's in-process query cannot trigger that build without VoiceOver.
//
// Solution: apps opt in by applying .appReveal("id") to SwiftUI views.
// The modifier measures native window coordinates and registers
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

    struct RegisteredElement {
        let id: String
        let frame: CGRect
        let label: String?
        let type: ElementType
        let windowId: String?
        let activate: (() -> Void)?
        let enabled: Bool

        var actions: [String] {
            guard enabled else { return [] }
            switch type {
            case .textField:
                return ["tap", "type", "clear"]
            case .label, .image, .other:
                return []
            default:
                return ["tap"]
            }
        }

        var isTappable: Bool {
            actions.contains("tap")
        }
    }

    private var entries: [String: RegisteredElement] = [:]
    private var pendingUnregisterTokens: [String: UUID] = [:]

    private init() {}

    func register(
        id: String,
        frame: CGRect,
        label: String?,
        type: ElementType = .button,
        activate: (() -> Void)? = nil,
        windowId: String? = nil,
        enabled: Bool = true
    ) {
        pendingUnregisterTokens[id] = nil
        entries[id] = RegisteredElement(
            id: id,
            frame: frame,
            label: label,
            type: type,
            windowId: windowId ?? Self.windowId(containing: frame),
            activate: activate,
            enabled: enabled
        )
    }

    func unregister(id: String) {
        let token = UUID()
        pendingUnregisterTokens[id] = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard pendingUnregisterTokens[id] == token else { return }
            entries.removeValue(forKey: id)
            pendingUnregisterTokens[id] = nil
        }
    }

    func currentElements(windowIds: Set<String>) -> [RegisteredElement] {
        entries.compactMap { id, entry in
            guard Self.entry(entry, matchesAnyOf: windowIds) else { return nil }
            return RegisteredElement(
                id: id,
                frame: entry.frame,
                label: entry.label,
                type: entry.type,
                windowId: entry.windowId,
                activate: entry.activate,
                enabled: entry.enabled
            )
        }
    }

    func findElement(byId id: String, windowIds: Set<String>) -> RegisteredElement? {
        guard let entry = entries[id] else { return nil }
        guard Self.entry(entry, matchesAnyOf: windowIds) else { return nil }
        return entry
    }

    func findTappableElement(at point: CGPoint, windowIds: Set<String>) -> RegisteredElement? {
        entries.values
            .filter { entry in
                entry.isTappable &&
                    entry.frame.contains(point) &&
                    Self.entry(entry, matchesAnyOf: windowIds)
            }
            .min { lhs, rhs in
                lhs.frame.area < rhs.frame.area
            }
    }

    func matchingElements(text: String, matchMode: String, windowIds: Set<String>) -> [RegisteredElement] {
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
            return matches ? entry : nil
        }
    }

    func activate(id: String) -> Bool {
        guard let entry = entries[id], entry.enabled, let activate = entry.activate else {
            return false
        }

        activate()
        return true
    }

    private static func entry(_ entry: RegisteredElement, matchesAnyOf windowIds: Set<String>) -> Bool {
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
    var area: CGFloat { width * height }
}

// MARK: - Native frame measurement

// SwiftUI's .global space belongs to its hosting view, not necessarily to the
// window. In AppKit it also has the opposite Y axis. Measure in the actual
// window so embedded hosts and overlapping windows cannot target another view.
#if os(iOS)
private final class AppRevealFrameView: UIView {
    var report: ((CGRect, String) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); reportFrame() }
    override func layoutSubviews() { super.layoutSubviews(); reportFrame() }
    func reportFrame() {
        guard let window, !bounds.isEmpty else { return }
        let id = window.accessibilityIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? "window-\(ObjectIdentifier(window).hashValue)"
        report?(convert(bounds, to: window), id)
    }
}

private struct AppRevealFrameReader: UIViewRepresentable {
    let layoutFrame: CGRect
    let report: (CGRect, String) -> Void
    func makeUIView(context: Context) -> AppRevealFrameView { AppRevealFrameView() }
    func updateUIView(_ view: AppRevealFrameView, context: Context) {
        view.report = report
        view.reportFrame()
    }
}
#elseif os(macOS)
private final class AppRevealFrameView: NSView {
    var report: ((CGRect, String) -> Void)?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); reportFrame() }
    override func layout() { super.layout(); reportFrame() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); reportFrame() }
    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); reportFrame() }
    func reportFrame() {
        guard let window, !bounds.isEmpty else { return }
        let id = window.identifier?.rawValue ?? "window_\(window.windowNumber)"
        report?(convert(bounds, to: nil), id)
    }
}

private struct AppRevealFrameReader: NSViewRepresentable {
    let layoutFrame: CGRect
    let report: (CGRect, String) -> Void
    func makeNSView(context: Context) -> AppRevealFrameView { AppRevealFrameView() }
    func updateNSView(_ view: AppRevealFrameView, context: Context) {
        view.report = report
        view.reportFrame()
    }
}
#endif

struct AppRevealModifier: ViewModifier {
    let id: String
    let label: String?
    let type: ElementType
    let activate: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    AppRevealFrameReader(layoutFrame: geometry.frame(in: .global)) { frame, windowId in
                        Task { @MainActor in
                            SwiftUIElementRegistry.shared.register(
                                id: id, frame: frame, label: label, type: type,
                                activate: activate, windowId: windowId, enabled: isEnabled
                            )
                        }
                    }.allowsHitTesting(false)
                }.allowsHitTesting(false)
            )
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
    ///   - type: Element type AppReveal should advertise for this view.
    ///   - activate: Optional direct debug activation closure. Use this for SwiftUI
    ///     controls whose gestures are intercepted by ScrollView/Lazy containers.
    func appReveal(
        _ id: String,
        label: String? = nil,
        type: ElementType = .button,
        activate: (() -> Void)? = nil
    ) -> some View {
        modifier(AppRevealModifier(id: id, label: label, type: type, activate: activate))
    }
}

#endif

#endif
