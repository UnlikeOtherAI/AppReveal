// Enumerates visible interactive elements from the view hierarchy

import Foundation
import UIKit

#if DEBUG

@MainActor
final class ElementInventory {

    static let shared = ElementInventory()

    private init() {}

    func listElements() -> [ElementInfo] {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else {
            return []
        }

        var elements: [ElementInfo] = []
        walkView(window, elements: &elements, containerId: nil)
        return elements
    }

    func findElement(byId id: String) -> UIView? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else {
            return nil
        }
        return findView(withAccessibilityId: id, in: window)
    }

    // MARK: - Hierarchy walking

    private func walkView(_ view: UIView, elements: inout [ElementInfo], containerId: String?) {
        let id = view.accessibilityIdentifier

        // Only include views with accessibility identifiers or that are interactive
        if id != nil || isInteractive(view) {
            if let info = makeElementInfo(view, containerId: containerId) {
                elements.append(info)
            }
        }

        let currentContainerId = id ?? containerId
        for subview in view.subviews where !subview.isHidden {
            walkView(subview, elements: &elements, containerId: currentContainerId)
        }
    }

    private func isInteractive(_ view: UIView) -> Bool {
        view is UIButton ||
        view is UITextField ||
        view is UITextView ||
        view is UISwitch ||
        view is UISlider ||
        view is UIStepper
    }

    private func makeElementInfo(_ view: UIView, containerId: String?) -> ElementInfo? {
        guard let id = view.accessibilityIdentifier, !id.isEmpty else {
            // Only include interactive views without IDs
            guard isInteractive(view) else { return nil }
            return nil
        }

        let screenFrame = view.convert(view.bounds, to: nil)

        return ElementInfo(
            id: id,
            type: classifyView(view),
            label: view.accessibilityLabel,
            value: view.accessibilityValue,
            enabled: view.isUserInteractionEnabled && (view as? UIControl)?.isEnabled ?? true,
            visible: !view.isHidden && view.alpha > 0,
            tappable: view is UIControl || view.gestureRecognizers?.isEmpty == false,
            frame: ElementInfo.ElementFrame(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.size.width,
                height: screenFrame.size.height
            ),
            containerId: containerId,
            actions: availableActions(for: view)
        )
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
        if view is UIControl || view.gestureRecognizers?.isEmpty == false {
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

    // MARK: - Full view tree

    func dumpViewTree(maxDepth: Int = 50) -> [[String: Any]] {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else {
            return []
        }
        return dumpNode(window, depth: 0, maxDepth: maxDepth)
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

#endif
