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
