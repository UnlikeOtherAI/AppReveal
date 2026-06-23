// Enumerates visible interactive elements from the view hierarchy

import Foundation

#if os(iOS)

import UIKit

#if DEBUG

@MainActor
final class ElementInventory {

    static let shared = ElementInventory()

    private init() {}

    func listElements(windowId: String? = nil) -> [ElementInfo] {
        let windows = candidateWindows(windowId: windowId)
        guard !windows.isEmpty else {
            return []
        }

        var elements: [ElementInfo] = []
        var seenIds: [String: Int] = [:]
        var seenAccessibilityElements: Set<ObjectIdentifier> = []
        for ref in windows {
            walkView(
                ref.nativeWindow,
                elements: &elements,
                seenIds: &seenIds,
                containerId: nil,
                seenAccessibilityElements: &seenAccessibilityElements
            )
        }
        appendSwiftUIRegisteredElements(to: &elements, seenIds: &seenIds, windowIds: Set(windows.map(\.id)))
        return elements
    }

    func findElement(byId id: String, windowId: String? = nil) -> UIView? {
        let windows = candidateWindows(windowId: windowId)
        for ref in windows {
            var seenIds: [String: Int] = [:]
            if let view = findView(byListedId: id, in: ref.nativeWindow, containerId: nil, seenIds: &seenIds) {
                return view
            }

            if let view = findViewByExactText(id, in: ref.nativeWindow),
               let tappable = Self.findTappableAncestor(of: view) {
                return tappable
            }
        }
        return nil
    }

    /// Find element by visible text with ambiguity handling.
    func findElementByText(
        _ text: String,
        matchMode: String = "exact",
        occurrence: Int = 0,
        windowId: String? = nil
    ) -> TextResolveResult {
        let windows = candidateWindows(windowId: windowId)
        guard !windows.isEmpty else {
            return TextResolveResult(error: "No window available")
        }

        var matches: [(view: UIView, text: String)] = []
        for ref in windows {
            collectTextMatches(text, matchMode: matchMode, in: ref.nativeWindow, matches: &matches)
        }

        if matches.isEmpty {
            return TextResolveResult(error: "No element with text \"\(text)\" found on the current screen.")
        }

        // Walk each match up to a tappable ancestor
        var tappableCandidates: [(view: UIView, label: String)] = []
        for match in matches {
            if let tappable = Self.findTappableAncestor(of: match.view) {
                tappableCandidates.append((tappable, match.text))
            }
        }

        if tappableCandidates.isEmpty {
            return TextResolveResult(error: "Text \"\(text)\" found but no tappable ancestor. The text is a static label.")
        }

        if tappableCandidates.count > 1 && occurrence >= tappableCandidates.count {
            return TextResolveResult(
                error: "occurrence \(occurrence) out of range (found \(tappableCandidates.count) matches)",
                candidates: tappableCandidates.map { $0.label }
            )
        }

        if tappableCandidates.count > 1 && occurrence < 0 {
            return TextResolveResult(
                error: "Ambiguous: \(tappableCandidates.count) matches found. Use occurrence (0-based) to disambiguate.",
                candidates: tappableCandidates.map { $0.label }
            )
        }

        let index = tappableCandidates.count == 1 ? 0 : occurrence
        return TextResolveResult(view: tappableCandidates[index].view)
    }

    func findTapTarget(byId id: String, windowId: String? = nil) -> TapTarget? {
        let windows = candidateWindows(windowId: windowId)
        for ref in windows {
            var seenIds: [String: Int] = [:]
            if let view = findView(byListedId: id, in: ref.nativeWindow, containerId: nil, seenIds: &seenIds) {
                return .view(view)
            }

            if let view = findViewByExactText(id, in: ref.nativeWindow),
               let tappable = Self.findTappableAncestor(of: view) {
                return .view(tappable)
            }

            if let accessibilityTarget = AccessibilityElementInventory.shared.findElement(byListedId: id, in: ref.nativeWindow) {
                return .accessibility(accessibilityTarget)
            }

            if let accessibilityTarget = AccessibilityElementInventory.shared.findElement(byVisibleText: id, in: ref.nativeWindow) {
                return .accessibility(accessibilityTarget)
            }
        }

        // Check elements registered via .appReveal() modifier (required for SwiftUI on iOS 26+).
        if let entry = SwiftUIElementRegistry.shared.findElement(byId: id, windowIds: Set(windows.map(\.id))) {
            return .appReveal(id: entry.id, point: entry.frame.center)
        }

        return nil
    }

    func findTapTargetByText(
        _ text: String,
        matchMode: String = "exact",
        occurrence: Int = 0,
        windowId: String? = nil
    ) -> TapTargetResolveResult {
        let windows = candidateWindows(windowId: windowId)
        guard !windows.isEmpty else {
            return TapTargetResolveResult(error: "No window available")
        }

        var candidates: [String] = []
        var resolvedTargets: [TapTarget] = []

        let windowIds = Set(windows.map(\.id))
        for ref in windows {
            var viewMatches: [(view: UIView, text: String)] = []
            collectTextMatches(text, matchMode: matchMode, in: ref.nativeWindow, matches: &viewMatches)
            for match in viewMatches {
                if let tappable = Self.findTappableAncestor(of: match.view) {
                    resolvedTargets.append(.view(tappable))
                    candidates.append(match.text)
                }
            }

            let accessibilityMatches = AccessibilityElementInventory.shared.collectTextMatches(
                text,
                matchMode: matchMode,
                in: ref.nativeWindow
            )
            for match in accessibilityMatches {
                resolvedTargets.append(.accessibility(match))
                candidates.append(match.label ?? match.id)
            }
        }

        for entry in SwiftUIElementRegistry.shared.matchingElements(text: text, matchMode: matchMode, windowIds: windowIds) {
            resolvedTargets.append(.appReveal(id: entry.id, point: entry.frame.center))
            candidates.append(entry.label ?? entry.id)
        }

        if resolvedTargets.isEmpty {
            return TapTargetResolveResult(error: "No element with text \"\(text)\" found on the current screen.")
        }

        if resolvedTargets.count > 1 && occurrence >= resolvedTargets.count {
            return TapTargetResolveResult(
                error: "occurrence \(occurrence) out of range (found \(resolvedTargets.count) matches)",
                candidates: candidates
            )
        }

        if resolvedTargets.count > 1 && occurrence < 0 {
            return TapTargetResolveResult(
                error: "Ambiguous: \(resolvedTargets.count) matches found. Use occurrence (0-based) to disambiguate.",
                candidates: candidates
            )
        }

        let index = resolvedTargets.count == 1 ? 0 : occurrence
        return TapTargetResolveResult(target: resolvedTargets[index])
    }

    // MARK: - Text utilities

    /// Extract visible text from a view.
    static func extractText(from view: UIView) -> String? {
        if let button = view as? UIButton { return button.currentTitle }
        if let label = view as? UILabel { return label.text }
        if let textField = view as? UITextField { return textField.placeholder ?? textField.text }
        if let textView = view as? UITextView { return textView.text }
        // Walk immediate children for labels
        for sub in view.subviews {
            if let label = sub as? UILabel, let text = label.text, !text.isEmpty {
                return text
            }
        }
        return view.accessibilityLabel
    }

    /// Normalize text to a stable ID (lowercase, underscored, stripped).
    static func normalizeToId(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "unnamed" }
        var normalized = trimmed.lowercased()
        normalized = normalized.replacingOccurrences(
            of: "\\s+", with: "_", options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: "[^a-z0-9_]", with: "", options: .regularExpression
        )
        if normalized.isEmpty { return "unnamed" }
        return String(normalized.prefix(40))
    }

    /// Find tappable ancestor of a view.
    static func findTappableAncestor(of view: UIView) -> UIView? {
        var current: UIView? = view
        var depth = 0
        while let v = current, depth < 50 {
            if v is UIControl { return v }
            if let gr = v.gestureRecognizers, !gr.isEmpty { return v }
            if v is UITableViewCell || v is UICollectionViewCell { return v }
            current = v.superview
            depth += 1
        }
        return nil
    }

    // MARK: - Hierarchy walking

    private func walkView(
        _ view: UIView,
        elements: inout [ElementInfo],
        seenIds: inout [String: Int],
        containerId: String?,
        seenAccessibilityElements: inout Set<ObjectIdentifier>
    ) {
        let accessId = view.accessibilityIdentifier

        if accessId != nil || isInteractive(view) || view.isAccessibilityElement {
            if let info = makeElementInfo(view, containerId: containerId, seenIds: &seenIds) {
                elements.append(info)
            }
        }

        let currentContainerId = accessId ?? containerId
        AccessibilityElementInventory.shared.appendElements(
            in: view,
            elements: &elements,
            seenIds: &seenIds,
            containerId: currentContainerId,
            visited: &seenAccessibilityElements
        )
        for subview in view.subviews where !subview.isHidden {
            walkView(
                subview,
                elements: &elements,
                seenIds: &seenIds,
                containerId: currentContainerId,
                seenAccessibilityElements: &seenAccessibilityElements
            )
        }
    }

    private func isInteractive(_ view: UIView) -> Bool {
        view is UIButton ||
        view is UITextField ||
        view is UITextView ||
        view is UISwitch ||
        view is UISlider ||
        view is UIStepper ||
        view is UISegmentedControl ||
        (view.isUserInteractionEnabled && view.gestureRecognizers?.isEmpty == false) ||
        view is UITableViewCell ||
        view is UICollectionViewCell
    }

    private func makeElementInfo(_ view: UIView, containerId: String?, seenIds: inout [String: Int]) -> ElementInfo? {
        let (id, idSource) = resolveId(for: view)
        guard let resolvedId = id else { return nil }

        // Dedup
        let finalId: String
        let count = seenIds[resolvedId, default: 0]
        seenIds[resolvedId] = count + 1
        finalId = count == 0 ? resolvedId : "\(resolvedId)_\(count)"

        let screenFrame = view.convert(view.bounds, to: nil)
        let layoutGuideFrame = view.convert(view.safeAreaLayoutGuide.layoutFrame, to: nil)
        let safeAreaInsets = Self.makeSafeAreaInsets(
            view.safeAreaInsets,
            layoutDirection: view.effectiveUserInterfaceLayoutDirection
        )

        return ElementInfo(
            id: finalId,
            type: classifyView(view),
            label: view.accessibilityLabel ?? Self.extractText(from: view),
            value: view.accessibilityValue,
            enabled: view.isUserInteractionEnabled && (view as? UIControl)?.isEnabled ?? true,
            visible: !view.isHidden && view.alpha > 0,
            tappable: view is UIControl || view.gestureRecognizers?.isEmpty == false || view is UITableViewCell || view is UICollectionViewCell,
            frame: Self.makeFrame(screenFrame),
            safeAreaInsets: safeAreaInsets,
            safeAreaLayoutGuideFrame: Self.makeFrame(layoutGuideFrame),
            containerId: containerId,
            actions: availableActions(for: view),
            idSource: idSource
        )
    }

    private func resolveId(for view: UIView) -> (String?, String) {
        // 1. Explicit accessibilityIdentifier
        if let id = view.accessibilityIdentifier, !id.isEmpty {
            return (id, "explicit")
        }
        // 2. accessibilityLabel → semantics
        if let label = view.accessibilityLabel, !label.isEmpty {
            return (Self.normalizeToId(label), "semantics")
        }
        // 3. Visible text → text
        if let text = Self.extractText(from: view), !text.isEmpty {
            return (Self.normalizeToId(text), "text")
        }
        // 4. Derived from type
        if isInteractive(view) {
            let typeName = String(describing: type(of: view))
                .lowercased()
                .replacingOccurrences(of: "ui", with: "")
            return (typeName, "derived")
        }
        return (nil, "derived")
    }

    private func classifyView(_ view: UIView) -> ElementType {
        switch view {
        case is UIButton: return .button
        case is UITextField: return .textField
        case is UILabel: return .label
        case is UIImageView: return .image
        case is UISwitch: return .toggle
        case is UISlider: return .slider
        case is UIStepper: return .stepper
        case is UITableViewCell: return .cell
        case is UICollectionViewCell: return .cell
        case is UITableView: return .tableView
        case is UICollectionView: return .collectionView
        case is UIScrollView: return .scrollView
        case is UINavigationBar: return .navigationBar
        case is UITabBar: return .tabBar
        default: return .other
        }
    }

    private func availableActions(for view: UIView) -> [String] {
        var actions: [String] = []
        if view is UIControl || view.gestureRecognizers?.isEmpty == false || view is UITableViewCell || view is UICollectionViewCell {
            actions.append("tap")
        }
        if view is UITextField || view is UITextView {
            actions.append("type")
            actions.append("clear")
        }
        if view is UIScrollView {
            actions.append("scroll")
        }
        return actions
    }

    // MARK: - Text matching

    private func collectTextMatches(_ query: String, matchMode: String, in view: UIView, matches: inout [(view: UIView, text: String)]) {
        if let text = Self.extractText(from: view), !text.isEmpty {
            let isMatch: Bool
            switch matchMode {
            case "contains":
                isMatch = text.localizedCaseInsensitiveContains(query)
            default:
                isMatch = text == query
            }
            if isMatch {
                matches.append((view, text))
            }
        }
        for subview in view.subviews where !subview.isHidden {
            collectTextMatches(query, matchMode: matchMode, in: subview, matches: &matches)
        }
    }

    private func findViewByExactText(_ text: String, in view: UIView) -> UIView? {
        if let viewText = Self.extractText(from: view), viewText == text {
            return view
        }
        for subview in view.subviews {
            if let found = findViewByExactText(text, in: subview) {
                return found
            }
        }
        return nil
    }

    private func findView(matching predicate: (UIView) -> Bool, in view: UIView) -> UIView? {
        if predicate(view) { return view }
        for subview in view.subviews {
            if let found = findView(matching: predicate, in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Full view tree

    func dumpViewTree(maxDepth: Int = 50, windowId: String? = nil) -> [[String: Any]] {
        let windows = candidateWindows(windowId: windowId)
        guard !windows.isEmpty else {
            return []
        }
        var seenAccessibilityElements: Set<ObjectIdentifier> = []
        var result: [[String: Any]] = []
        for ref in windows {
            result.append(
                contentsOf: dumpNode(
                    ref.nativeWindow,
                    depth: 0,
                    maxDepth: maxDepth,
                    seenAccessibilityElements: &seenAccessibilityElements
                )
            )
        }
        appendSwiftUIRegisteredViewTreeNodes(to: &result, windowIds: Set(windows.map(\.id)))
        return result
    }

    private func dumpNode(
        _ view: UIView,
        depth: Int,
        maxDepth: Int,
        seenAccessibilityElements: inout Set<ObjectIdentifier>
    ) -> [[String: Any]] {
        guard depth < maxDepth else { return [] }

        let screenFrame = view.convert(view.bounds, to: nil)
        let layoutGuideFrame = view.convert(view.safeAreaLayoutGuide.layoutFrame, to: nil)
        var node: [String: Any] = [
            "class": String(describing: type(of: view)),
            "frame": "\(Int(screenFrame.origin.x)),\(Int(screenFrame.origin.y)),\(Int(screenFrame.size.width)),\(Int(screenFrame.size.height))",
            "safeAreaInsets": Self.dictionary(
                for: Self.makeSafeAreaInsets(
                    view.safeAreaInsets,
                    layoutDirection: view.effectiveUserInterfaceLayoutDirection
                )
            ),
            "safeAreaLayoutGuideFrame": Self.dictionary(for: Self.makeFrame(layoutGuideFrame)),
            "hidden": view.isHidden,
            "alpha": view.alpha,
            "userInteraction": view.isUserInteractionEnabled,
            "depth": depth
        ]

        if let id = view.accessibilityIdentifier, !id.isEmpty {
            node["accessibilityId"] = id
        }
        if let label = view.accessibilityLabel, !label.isEmpty {
            node["accessibilityLabel"] = label
        }
        if let value = view.accessibilityValue, !value.isEmpty {
            node["accessibilityValue"] = value
        }

        // Type-specific properties
        if let label = view as? UILabel {
            node["text"] = label.text ?? ""
            node["font"] = "\(label.font.fontName) \(label.font.pointSize)"
        } else if let textField = view as? UITextField {
            node["text"] = textField.text ?? ""
            node["placeholder"] = textField.placeholder ?? ""
            node["isEditing"] = textField.isEditing
        } else if let textView = view as? UITextView {
            node["text"] = String(textView.text.prefix(200))
            node["isEditable"] = textView.isEditable
        } else if let button = view as? UIButton {
            node["title"] = button.currentTitle ?? ""
            node["enabled"] = button.isEnabled
        } else if let imageView = view as? UIImageView {
            node["hasImage"] = imageView.image != nil
        } else if let toggle = view as? UISwitch {
            node["isOn"] = toggle.isOn
        } else if let slider = view as? UISlider {
            node["value"] = slider.value
            node["min"] = slider.minimumValue
            node["max"] = slider.maximumValue
        } else if let stepper = view as? UIStepper {
            node["value"] = stepper.value
        } else if let segmented = view as? UISegmentedControl {
            node["selectedIndex"] = segmented.selectedSegmentIndex
            node["segments"] = (0..<segmented.numberOfSegments).map {
                segmented.titleForSegment(at: $0) ?? "\($0)"
            }
        } else if let control = view as? UIControl {
            node["enabled"] = control.isEnabled
            node["selected"] = control.isSelected
        }

        if let gestures = view.gestureRecognizers, !gestures.isEmpty {
            node["gestureRecognizers"] = gestures.map { String(describing: type(of: $0)) }
        }

        var result = [node]
        AccessibilityElementInventory.shared.appendViewTreeNodes(
            for: view,
            depth: depth + 1,
            maxDepth: maxDepth,
            result: &result,
            visited: &seenAccessibilityElements
        )
        for subview in view.subviews {
            result.append(
                contentsOf: dumpNode(
                    subview,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    seenAccessibilityElements: &seenAccessibilityElements
                )
            )
        }
        return result
    }

    private func findView(
        byListedId targetId: String,
        in view: UIView,
        containerId: String?,
        seenIds: inout [String: Int]
    ) -> UIView? {
        let accessId = view.accessibilityIdentifier

        if accessId != nil || isInteractive(view) {
            let (id, _) = resolveId(for: view)
            if let resolvedId = id {
                let count = seenIds[resolvedId, default: 0]
                seenIds[resolvedId] = count + 1
                let finalId = count == 0 ? resolvedId : "\(resolvedId)_\(count)"
                if finalId == targetId {
                    return view
                }
            }
        }

        let currentContainerId = accessId ?? containerId
        for subview in view.subviews where !subview.isHidden {
            if let found = findView(byListedId: targetId, in: subview, containerId: currentContainerId, seenIds: &seenIds) {
                return found
            }
        }
        return nil
    }

    static func makeFrame(_ rect: CGRect) -> ElementInfo.ElementFrame {
        ElementInfo.ElementFrame(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    static func makeSafeAreaInsets(
        _ insets: UIEdgeInsets,
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> ElementInfo.ElementInsets {
        let isRightToLeft = layoutDirection == .rightToLeft
        return ElementInfo.ElementInsets(
            top: insets.top,
            leading: isRightToLeft ? insets.right : insets.left,
            bottom: insets.bottom,
            trailing: isRightToLeft ? insets.left : insets.right
        )
    }

    private static func dictionary(for frame: ElementInfo.ElementFrame) -> [String: Double] {
        [
            "x": frame.x,
            "y": frame.y,
            "width": frame.width,
            "height": frame.height
        ]
    }

    private static func dictionary(for insets: ElementInfo.ElementInsets) -> [String: Double] {
        [
            "top": insets.top,
            "leading": insets.leading,
            "bottom": insets.bottom,
            "trailing": insets.trailing
        ]
    }

    private func appendSwiftUIRegisteredElements(
        to elements: inout [ElementInfo],
        seenIds: inout [String: Int],
        windowIds: Set<String>
    ) {
        for entry in SwiftUIElementRegistry.shared.currentElements(windowIds: windowIds) {
            let count = seenIds[entry.id, default: 0]
            seenIds[entry.id] = count + 1
            let finalId = count == 0 ? entry.id : "\(entry.id)_\(count)"
            let frame = entry.frame
            let safeAreaInsets = ElementInfo.ElementInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            elements.append(
                ElementInfo(
                    id: finalId,
                    type: .button,
                    label: entry.label,
                    value: nil,
                    enabled: true,
                    visible: !frame.isEmpty,
                    tappable: true,
                    frame: Self.makeFrame(frame),
                    safeAreaInsets: safeAreaInsets,
                    safeAreaLayoutGuideFrame: Self.makeFrame(frame),
                    containerId: nil,
                    actions: ["tap"],
                    idSource: "appReveal"
                )
            )
        }
    }

    private func appendSwiftUIRegisteredViewTreeNodes(to result: inout [[String: Any]], windowIds: Set<String>) {
        for entry in SwiftUIElementRegistry.shared.currentElements(windowIds: windowIds) {
            let frame = entry.frame
            var node: [String: Any] = [
                "class": "SwiftUI.AppRevealElement",
                "frame": "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))",
                "hidden": frame.isEmpty,
                "alpha": 1,
                "userInteraction": true,
                "depth": 0,
                "accessibilityId": entry.id,
                "idSource": "appReveal",
                "actions": ["tap"]
            ]
            if let label = entry.label, !label.isEmpty {
                node["accessibilityLabel"] = label
            }
            result.append(node)
        }
    }

    private func candidateWindows(windowId: String?) -> [WindowRef] {
        IOSWindowProvider.shared.windowsForInteraction(windowId: windowId)
    }
}

/// Result of text-based element resolution.
struct TextResolveResult {
    let view: UIView?
    let error: String?
    let candidates: [String]?

    var isSuccess: Bool { view != nil }

    init(view: UIView) {
        self.view = view
        self.error = nil
        self.candidates = nil
    }

    init(error: String, candidates: [String]? = nil) {
        self.view = nil
        self.error = error
        self.candidates = candidates
    }
}

#endif

#endif
