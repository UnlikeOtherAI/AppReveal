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
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return []
        }

        var elements: [ElementInfo] = []
        var seenIds: [String: Int] = [:]
        walkView(ref.nativeWindow, elements: &elements, seenIds: &seenIds, containerId: nil)
        return elements
    }

    func findElement(byId id: String, windowId: String? = nil) -> UIView? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return nil
        }
        // 1. Exact accessibilityIdentifier match
        if let view = findView(withAccessibilityId: id, in: ref.nativeWindow) {
            return view
        }
        // 2. Try accessibilityLabel match
        if let view = findView(matching: { Self.normalizeToId($0.accessibilityLabel ?? "") == id }, in: ref.nativeWindow) {
            return view
        }
        // 3. Try derived text ID match on interactive views
        if let view = findView(matching: { view in
            guard self.isInteractive(view) else { return false }
            guard let text = Self.extractText(from: view) else { return false }
            return Self.normalizeToId(text) == id
        }, in: ref.nativeWindow) {
            return view
        }
        // 4. Try exact visible text → tappable ancestor
        if let view = findViewByExactText(id, in: ref.nativeWindow),
           let tappable = Self.findTappableAncestor(of: view) {
            return tappable
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
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return TextResolveResult(error: "No window available")
        }

        var matches: [(view: UIView, text: String)] = []
        collectTextMatches(text, matchMode: matchMode, in: ref.nativeWindow, matches: &matches)

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

    private func walkView(_ view: UIView, elements: inout [ElementInfo], seenIds: inout [String: Int], containerId: String?) {
        let accessId = view.accessibilityIdentifier

        if accessId != nil || isInteractive(view) {
            if let info = makeElementInfo(view, containerId: containerId, seenIds: &seenIds) {
                elements.append(info)
            }
        }

        let currentContainerId = accessId ?? containerId
        for subview in view.subviews where !subview.isHidden {
            walkView(subview, elements: &elements, seenIds: &seenIds, containerId: currentContainerId)
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

        return ElementInfo(
            id: finalId,
            type: classifyView(view),
            label: view.accessibilityLabel ?? Self.extractText(from: view),
            value: view.accessibilityValue,
            enabled: view.isUserInteractionEnabled && (view as? UIControl)?.isEnabled ?? true,
            visible: !view.isHidden && view.alpha > 0,
            tappable: view is UIControl || view.gestureRecognizers?.isEmpty == false || view is UITableViewCell || view is UICollectionViewCell,
            frame: ElementInfo.ElementFrame(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.size.width,
                height: screenFrame.size.height
            ),
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
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return []
        }
        return dumpNode(ref.nativeWindow, depth: 0, maxDepth: maxDepth)
    }

    private func dumpNode(_ view: UIView, depth: Int, maxDepth: Int) -> [[String: Any]] {
        guard depth < maxDepth else { return [] }

        let screenFrame = view.convert(view.bounds, to: nil)
        var node: [String: Any] = [
            "class": String(describing: type(of: view)),
            "frame": "\(Int(screenFrame.origin.x)),\(Int(screenFrame.origin.y)),\(Int(screenFrame.size.width)),\(Int(screenFrame.size.height))",
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
        for subview in view.subviews {
            result.append(contentsOf: dumpNode(subview, depth: depth + 1, maxDepth: maxDepth))
        }
        return result
    }

    private func findView(withAccessibilityId id: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == id { return view }
        for subview in view.subviews {
            if let found = findView(withAccessibilityId: id, in: subview) {
                return found
            }
        }
        return nil
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
