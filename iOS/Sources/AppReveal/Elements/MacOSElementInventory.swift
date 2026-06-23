// macOS AppKit implementation of element inventory -- walks NSView hierarchy

import Foundation

#if DEBUG
#if os(macOS)

import AppKit

@MainActor
final class ElementInventory {

    static let shared = ElementInventory()

    private init() {}

    func listElements(windowId: String? = nil) -> [ElementInfo] {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let contentView = ref.contentView else {
            return []
        }

        var elements: [ElementInfo] = []
        var seenIds: [String: Int] = [:]
        walkView(contentView, elements: &elements, seenIds: &seenIds, containerId: nil)
        appendSwiftUIRegisteredElements(to: &elements, seenIds: &seenIds, windowIds: Set([ref.id]))
        return elements
    }

    func findElement(byId id: String, windowId: String? = nil) -> NSView? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let contentView = ref.contentView else {
            return nil
        }
        var seenIds: [String: Int] = [:]
        if let view = findView(byListedId: id, in: contentView, containerId: nil, seenIds: &seenIds) {
            return view
        }
        return nil
    }

    /// Find element by visible text with ambiguity handling.
    func findElementByText(
        _ text: String,
        matchMode: String = "exact",
        occurrence: Int = 0,
        windowId: String? = nil
    ) -> MacOSTextResolveResult {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let contentView = ref.contentView else {
            return MacOSTextResolveResult(error: "No window available")
        }

        var matches: [(view: NSView, text: String)] = []
        collectTextMatches(text, matchMode: matchMode, in: contentView, matches: &matches)

        var resolvedTargets: [(view: NSView?, appRevealId: String?, point: CGPoint?, label: String)] = []
        for match in matches {
            if let tappable = Self.findTappableAncestor(of: match.view) {
                resolvedTargets.append((tappable, nil, nil, match.text))
            }
        }

        for entry in SwiftUIElementRegistry.shared.matchingElements(text: text, matchMode: matchMode, windowIds: Set([ref.id])) {
            resolvedTargets.append((nil, entry.id, entry.frame.center, entry.label ?? entry.id))
        }

        if matches.isEmpty && resolvedTargets.isEmpty {
            return MacOSTextResolveResult(error: "No element with text \"\(text)\" found on the current screen.")
        }

        if resolvedTargets.isEmpty {
            return MacOSTextResolveResult(error: "Text \"\(text)\" found but no tappable ancestor. The text is a static label.")
        }

        if resolvedTargets.count > 1 && occurrence < 0 {
            return MacOSTextResolveResult(
                error: "Ambiguous: \(resolvedTargets.count) matches found. Use occurrence (0-based) to disambiguate.",
                candidates: resolvedTargets.map { $0.label }
            )
        }

        if occurrence >= resolvedTargets.count {
            return MacOSTextResolveResult(
                error: "occurrence \(occurrence) out of range (found \(resolvedTargets.count) matches)",
                candidates: resolvedTargets.map { $0.label }
            )
        }

        let index = resolvedTargets.count == 1 ? 0 : occurrence
        let target = resolvedTargets[index]
        if let view = target.view {
            return MacOSTextResolveResult(view: view)
        }
        return MacOSTextResolveResult(appRevealId: target.appRevealId, point: target.point)
    }

    // MARK: - Text utilities

    static func extractText(from view: NSView) -> String? {
        if let button = view as? NSButton { return button.title.isEmpty ? nil : button.title }
        if let textField = view as? NSTextField { return textField.stringValue.isEmpty ? textField.placeholderString : textField.stringValue }
        if let textView = view as? NSTextView { return textView.string.isEmpty ? nil : textView.string }
        // Walk immediate children
        for sub in view.subviews {
            if let textField = sub as? NSTextField, !textField.isEditable, !textField.stringValue.isEmpty {
                return textField.stringValue
            }
        }
        if let label = view.accessibilityLabel(), !label.isEmpty {
            return label
        }
        return nil
    }

    static func normalizeToId(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "unnamed" }
        var normalized = trimmed.lowercased()
        normalized = normalized.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        if normalized.isEmpty { return "unnamed" }
        return String(normalized.prefix(40))
    }

    static func findTappableAncestor(of view: NSView) -> NSView? {
        var current: NSView? = view
        var depth = 0
        while let v = current, depth < 50 {
            if v is NSButton || v is NSSegmentedControl { return v }
            if v is NSControl { return v }
            if v is NSTableRowView || v is NSTableCellView { return v }
            current = v.superview
            depth += 1
        }
        return nil
    }

    // MARK: - Hierarchy walking

    private func walkView(_ view: NSView, elements: inout [ElementInfo], seenIds: inout [String: Int], containerId: String?) {
        let accessId = view.accessibilityIdentifier()
        let hasId = !accessId.isEmpty

        if hasId || isInteractive(view) {
            if let info = makeElementInfo(view, containerId: containerId, seenIds: &seenIds) {
                elements.append(info)
            }
        }

        let currentContainerId = hasId ? accessId : containerId
        for subview in view.subviews where !subview.isHiddenOrHasHiddenAncestor {
            walkView(subview, elements: &elements, seenIds: &seenIds, containerId: currentContainerId)
        }
    }

    private func isInteractive(_ view: NSView) -> Bool {
        view is NSButton ||
        view is NSTextField ||
        view is NSTextView ||
        view is NSSwitch ||
        view is NSSlider ||
        view is NSStepper ||
        view is NSPopUpButton ||
        view is NSComboBox ||
        view is NSSegmentedControl ||
        view is NSTableRowView
    }

    private func makeElementInfo(_ view: NSView, containerId: String?, seenIds: inout [String: Int]) -> ElementInfo? {
        let (id, idSource) = resolveId(for: view)
        guard let resolvedId = id else { return nil }

        let count = seenIds[resolvedId, default: 0]
        seenIds[resolvedId] = count + 1
        let finalId = count == 0 ? resolvedId : "\(resolvedId)_\(count)"

        let windowFrame = view.convert(view.bounds, to: nil)
        let layoutGuideFrame = view.convert(view.safeAreaRect, to: nil)
        let safeAreaInsets = Self.makeSafeAreaInsets(
            view.safeAreaInsets,
            layoutDirection: view.userInterfaceLayoutDirection
        )

        return ElementInfo(
            id: finalId,
            type: classifyView(view),
            label: view.accessibilityLabel() ?? Self.extractText(from: view),
            value: view.accessibilityValue() as? String,
            enabled: (view as? NSControl)?.isEnabled ?? true,
            visible: !view.isHiddenOrHasHiddenAncestor,
            tappable: view is NSControl || view is NSTableView,
            frame: Self.makeFrame(windowFrame),
            safeAreaInsets: safeAreaInsets,
            safeAreaLayoutGuideFrame: Self.makeFrame(layoutGuideFrame),
            containerId: containerId,
            actions: availableActions(for: view),
            idSource: idSource
        )
    }

    private func resolveId(for view: NSView) -> (String?, String) {
        let accessId = view.accessibilityIdentifier()
        if !accessId.isEmpty {
            return (accessId, "explicit")
        }
        if let label = view.accessibilityLabel(), !label.isEmpty {
            return (Self.normalizeToId(label), "semantics")
        }
        if let text = Self.extractText(from: view), !text.isEmpty {
            return (Self.normalizeToId(text), "text")
        }
        if isInteractive(view) {
            let typeName = String(describing: type(of: view))
                .lowercased()
                .replacingOccurrences(of: "ns", with: "")
            return (typeName, "derived")
        }
        return (nil, "derived")
    }

    private func classifyView(_ view: NSView) -> ElementType {
        switch view {
        case is NSPopUpButton: return .picker
        case is NSComboBox: return .picker
        case is NSButton: return .button
        case is NSSwitch: return .toggle
        case let textField as NSTextField where textField.isEditable: return .textField
        case is NSTextField: return .label
        case is NSTextView: return .textField
        case is NSSlider: return .slider
        case is NSStepper: return .stepper
        case is NSTableView: return .tableView
        case is NSCollectionView: return .collectionView
        case is NSScrollView: return .scrollView
        case is NSImageView: return .image
        case is NSSegmentedControl: return .other
        default: return .other
        }
    }

    private func availableActions(for view: NSView) -> [String] {
        var actions: [String] = []
        if view is NSControl || view is NSTableView {
            actions.append("tap")
        }
        if view is NSTextView || (view as? NSTextField)?.isEditable == true {
            actions.append("type")
            actions.append("clear")
        }
        if view is NSScrollView {
            actions.append("scroll")
        }
        return actions
    }

    // MARK: - Text matching

    private func collectTextMatches(_ query: String, matchMode: String, in view: NSView, matches: inout [(view: NSView, text: String)]) {
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
        for subview in view.subviews where !subview.isHiddenOrHasHiddenAncestor {
            collectTextMatches(query, matchMode: matchMode, in: subview, matches: &matches)
        }
    }

    private func findView(matching predicate: (NSView) -> Bool, in view: NSView) -> NSView? {
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
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let contentView = ref.contentView else {
            return []
        }
        var nodes = dumpNode(contentView, depth: 0, maxDepth: maxDepth)
        appendSwiftUIRegisteredViewTreeNodes(to: &nodes, windowIds: Set([ref.id]))
        return nodes
    }

    private func dumpNode(_ view: NSView, depth: Int, maxDepth: Int) -> [[String: Any]] {
        guard depth < maxDepth else { return [] }

        let windowFrame = view.convert(view.bounds, to: nil)
        let layoutGuideFrame = view.convert(view.safeAreaRect, to: nil)
        var node: [String: Any] = [
            "class": String(describing: type(of: view)),
            "frame": "\(Int(windowFrame.origin.x)),\(Int(windowFrame.origin.y)),\(Int(windowFrame.size.width)),\(Int(windowFrame.size.height))",
            "safeAreaInsets": Self.dictionary(
                for: Self.makeSafeAreaInsets(
                    view.safeAreaInsets,
                    layoutDirection: view.userInterfaceLayoutDirection
                )
            ),
            "safeAreaLayoutGuideFrame": Self.dictionary(for: Self.makeFrame(layoutGuideFrame)),
            "hidden": view.isHidden,
            "alphaValue": view.alphaValue,
            "depth": depth
        ]

        let accessId = view.accessibilityIdentifier()
        if !accessId.isEmpty {
            node["accessibilityId"] = accessId
        }
        if let label = view.accessibilityLabel(), !label.isEmpty {
            node["accessibilityLabel"] = label
        }
        if let value = view.accessibilityValue() as? String, !value.isEmpty {
            node["accessibilityValue"] = value
        }

        if let popup = view as? NSPopUpButton {
            node["selectedIndex"] = popup.indexOfSelectedItem
            node["selectedTitle"] = popup.titleOfSelectedItem ?? ""
            node["enabled"] = popup.isEnabled
        } else if let button = view as? NSButton {
            node["title"] = button.title
            node["enabled"] = button.isEnabled
            node["state"] = button.state == .on ? "on" : (button.state == .off ? "off" : "mixed")
        } else if let toggle = view as? NSSwitch {
            node["state"] = toggle.state == .on ? "on" : "off"
        } else if let textField = view as? NSTextField {
            node["text"] = textField.stringValue
            node["isEditable"] = textField.isEditable
            node["placeholder"] = textField.placeholderString ?? ""
        } else if let textView = view as? NSTextView {
            node["text"] = String(textView.string.prefix(200))
            node["isEditable"] = textView.isEditable
        } else if let imageView = view as? NSImageView {
            node["hasImage"] = imageView.image != nil
        } else if let slider = view as? NSSlider {
            node["value"] = slider.doubleValue
            node["min"] = slider.minValue
            node["max"] = slider.maxValue
        } else if let stepper = view as? NSStepper {
            node["value"] = stepper.doubleValue
        } else if let segmented = view as? NSSegmentedControl {
            node["selectedIndex"] = segmented.selectedSegment
            node["segments"] = (0..<segmented.segmentCount).map {
                segmented.label(forSegment: $0) ?? "\($0)"
            }
        } else if let control = view as? NSControl {
            node["enabled"] = control.isEnabled
        }

        var result = [node]
        for subview in view.subviews {
            result.append(contentsOf: dumpNode(subview, depth: depth + 1, maxDepth: maxDepth))
        }
        return result
    }

    private func findView(
        byListedId targetId: String,
        in view: NSView,
        containerId: String?,
        seenIds: inout [String: Int]
    ) -> NSView? {
        let accessId = view.accessibilityIdentifier()
        let hasId = !accessId.isEmpty

        if hasId || isInteractive(view) {
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

        let currentContainerId = hasId ? accessId : containerId
        for subview in view.subviews where !subview.isHiddenOrHasHiddenAncestor {
            if let found = findView(byListedId: targetId, in: subview, containerId: currentContainerId, seenIds: &seenIds) {
                return found
            }
        }
        return nil
    }

    private static func makeFrame(_ rect: CGRect) -> ElementInfo.ElementFrame {
        ElementInfo.ElementFrame(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private static func makeSafeAreaInsets(
        _ insets: NSEdgeInsets,
        layoutDirection: NSUserInterfaceLayoutDirection
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

    private func appendSwiftUIRegisteredViewTreeNodes(to nodes: inout [[String: Any]], windowIds: Set<String>) {
        for entry in SwiftUIElementRegistry.shared.currentElements(windowIds: windowIds) {
            let frame = entry.frame
            var node: [String: Any] = [
                "class": "SwiftUI.AppRevealElement",
                "frame": "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))",
                "hidden": frame.isEmpty,
                "alphaValue": 1,
                "depth": 0,
                "accessibilityId": entry.id,
                "idSource": "appReveal",
                "actions": ["tap"]
            ]
            if let label = entry.label, !label.isEmpty {
                node["accessibilityLabel"] = label
            }
            nodes.append(node)
        }
    }
}

/// Result of text-based element resolution (macOS).
struct MacOSTextResolveResult {
    let view: NSView?
    let appRevealId: String?
    let point: CGPoint?
    let error: String?
    let candidates: [String]?

    var isSuccess: Bool { view != nil || appRevealId != nil || point != nil }

    init(view: NSView) {
        self.view = view
        self.appRevealId = nil
        self.point = nil
        self.error = nil
        self.candidates = nil
    }

    init(appRevealId: String?, point: CGPoint?) {
        self.view = nil
        self.appRevealId = appRevealId
        self.point = point
        self.error = nil
        self.candidates = nil
    }

    init(error: String, candidates: [String]? = nil) {
        self.view = nil
        self.appRevealId = nil
        self.point = nil
        self.error = error
        self.candidates = candidates
    }
}

#endif // os(macOS)
#endif // DEBUG
