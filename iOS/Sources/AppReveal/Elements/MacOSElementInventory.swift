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
        walkView(contentView, elements: &elements, containerId: nil)
        return elements
    }

    func findElement(byId id: String, windowId: String? = nil) -> NSView? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let contentView = ref.contentView else {
            return nil
        }
        return findView(withAccessibilityId: id, in: contentView)
    }

    // MARK: - Hierarchy walking

    private func walkView(_ view: NSView, elements: inout [ElementInfo], containerId: String?) {
        let id = view.accessibilityIdentifier()
        let hasId = !id.isEmpty

        if hasId || isInteractive(view) {
            if let info = makeElementInfo(view, containerId: containerId) {
                elements.append(info)
            }
        }

        let currentContainerId = hasId ? id : containerId
        for subview in view.subviews where !subview.isHiddenOrHasHiddenAncestor {
            walkView(subview, elements: &elements, containerId: currentContainerId)
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
        view is NSSegmentedControl
    }

    private func makeElementInfo(_ view: NSView, containerId: String?) -> ElementInfo? {
        let id = view.accessibilityIdentifier()
        guard !id.isEmpty else {
            guard isInteractive(view) else { return nil }
            return nil
        }

        let windowFrame = view.convert(view.bounds, to: nil)

        return ElementInfo(
            id: id,
            type: classifyView(view),
            label: view.accessibilityLabel(),
            value: view.accessibilityValue() as? String,
            enabled: (view as? NSControl)?.isEnabled ?? true,
            visible: !view.isHiddenOrHasHiddenAncestor,
            tappable: view is NSControl || view is NSTableView,
            frame: ElementInfo.ElementFrame(
                x: windowFrame.origin.x,
                y: windowFrame.origin.y,
                width: windowFrame.size.width,
                height: windowFrame.size.height
            ),
            containerId: containerId,
            actions: availableActions(for: view)
        )
    }

    private func classifyView(_ view: NSView) -> ElementType {
        // NSPopUpButton / NSComboBox subclass NSButton, so check them first
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

    // MARK: - Full view tree

    func dumpViewTree(maxDepth: Int = 50, windowId: String? = nil) -> [[String: Any]] {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let contentView = ref.contentView else {
            return []
        }
        return dumpNode(contentView, depth: 0, maxDepth: maxDepth)
    }

    private func dumpNode(_ view: NSView, depth: Int, maxDepth: Int) -> [[String: Any]] {
        guard depth < maxDepth else { return [] }

        let windowFrame = view.convert(view.bounds, to: nil)
        var node: [String: Any] = [
            "class": String(describing: type(of: view)),
            "frame": "\(Int(windowFrame.origin.x)),\(Int(windowFrame.origin.y)),\(Int(windowFrame.size.width)),\(Int(windowFrame.size.height))",
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

        // Type-specific properties (NSPopUpButton before NSButton -- subclass)
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

    private func findView(withAccessibilityId id: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == id { return view }
        for subview in view.subviews {
            if let found = findView(withAccessibilityId: id, in: subview) {
                return found
            }
        }
        return nil
    }
}

#endif // os(macOS)
#endif // DEBUG
