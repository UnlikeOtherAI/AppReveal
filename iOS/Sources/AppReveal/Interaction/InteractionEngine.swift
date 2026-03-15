// Executes UI interactions (tap, type, scroll, navigate)

import Foundation
import UIKit

#if DEBUG

@MainActor
final class InteractionEngine {

    static let shared = InteractionEngine()

    private init() {}

    // MARK: - Tap

    func tap(elementId: String) throws {
        guard let view = ElementInventory.shared.findElement(byId: elementId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if let button = view as? UIButton {
            button.sendActions(for: .touchUpInside)
        } else if let control = view as? UIControl {
            control.sendActions(for: .touchUpInside)
        } else if let cell = view as? UITableViewCell,
                  let tableView = findParentTableView(of: view),
                  let indexPath = tableView.indexPath(for: cell) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            tableView.delegate?.tableView?(tableView, didSelectRowAt: indexPath)
        } else if let cell = view as? UICollectionViewCell,
                  let collectionView = findParentCollectionView(of: view),
                  let indexPath = collectionView.indexPath(for: cell) {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
        } else {
            // Simulate tap via gesture recognizers
            let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            tap(point: center)
        }
    }

    private func findParentTableView(of view: UIView) -> UITableView? {
        var current: UIView? = view.superview
        while let v = current {
            if let tv = v as? UITableView { return tv }
            current = v.superview
        }
        return nil
    }

    private func findParentCollectionView(of view: UIView) -> UICollectionView? {
        var current: UIView? = view.superview
        while let v = current {
            if let cv = v as? UICollectionView { return cv }
            current = v.superview
        }
        return nil
    }

    func tap(point: CGPoint) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else { return }

        let hitView = window.hitTest(point, with: nil)

        // Check if tapping inside a tab bar
        if let tabBar = findParent(of: hitView, type: UITabBar.self),
           let tabBarController = findTabBarController() {
            let localPoint = tabBar.convert(point, from: window)
            if let items = tabBar.items {
                let itemWidth = tabBar.bounds.width / CGFloat(items.count)
                let index = Int(localPoint.x / itemWidth)
                if index >= 0 && index < items.count {
                    tabBarController.selectedIndex = index
                    return
                }
            }
        }

        if let control = hitView as? UIControl {
            control.sendActions(for: .touchUpInside)
        } else {
            // Try to fire tap gesture recognizers on the view and its ancestors
            fireTapGestureRecognizers(on: hitView, at: point)
        }
    }

    private func fireTapGestureRecognizers(on view: UIView?, at point: CGPoint) {
        var current = view
        while let v = current {
            if let recognizers = v.gestureRecognizers {
                for recognizer in recognizers where recognizer is UITapGestureRecognizer && recognizer.isEnabled {
                    // Invoke the action associated with the recognizer
                    if let targets = recognizer.value(forKey: "_targets") as? [NSObject] {
                        for target in targets {
                            // Extract target and action from the internal representation
                            let description = String(describing: target)
                            if description.contains("action=") {
                                // Use performSelector-based invocation
                                recognizer.state = .ended
                                break
                            }
                        }
                    }
                    return
                }
            }
            current = v.superview
        }
    }

    private func findTabBarController() -> UITabBarController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return nil }
        return root as? UITabBarController
    }

    private func findParent<T: UIView>(of view: UIView?, type: T.Type) -> T? {
        var current: UIView? = view
        while let v = current {
            if let match = v as? T { return match }
            current = v.superview
        }
        return nil
    }

    // MARK: - Text

    func type(text: String, elementId: String?) throws {
        let target: UIView?

        if let id = elementId {
            target = ElementInventory.shared.findElement(byId: id)
            guard target != nil else {
                throw InteractionError.elementNotFound(id)
            }
        } else {
            target = UIResponder.currentFirstResponder as? UIView
        }

        if let textField = target as? UITextField {
            textField.becomeFirstResponder()
            textField.insertText(text)
        } else if let textView = target as? UITextView {
            textView.becomeFirstResponder()
            textView.insertText(text)
        } else {
            throw InteractionError.notEditable(elementId ?? "current responder")
        }
    }

    func clear(elementId: String) throws {
        guard let view = ElementInventory.shared.findElement(byId: elementId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if let textField = view as? UITextField {
            textField.text = ""
            textField.sendActions(for: .editingChanged)
        } else if let textView = view as? UITextView {
            textView.text = ""
        } else {
            throw InteractionError.notEditable(elementId)
        }
    }

    // MARK: - Scroll

    func scroll(direction: ScrollDirection, containerId: String?) throws {
        let scrollView: UIScrollView

        if let id = containerId {
            guard let view = ElementInventory.shared.findElement(byId: id) as? UIScrollView else {
                throw InteractionError.notScrollable(id)
            }
            scrollView = view
        } else {
            guard let found = findFirstScrollView() else {
                throw InteractionError.noScrollView
            }
            scrollView = found
        }

        let pageSize = direction.isVertical ? scrollView.bounds.height : scrollView.bounds.width
        var offset = scrollView.contentOffset

        switch direction {
        case .up:    offset.y = max(offset.y - pageSize * 0.8, 0)
        case .down:  offset.y = min(offset.y + pageSize * 0.8, scrollView.contentSize.height - scrollView.bounds.height)
        case .left:  offset.x = max(offset.x - pageSize * 0.8, 0)
        case .right: offset.x = min(offset.x + pageSize * 0.8, scrollView.contentSize.width - scrollView.bounds.width)
        }

        scrollView.setContentOffset(offset, animated: true)
    }

    func scrollTo(elementId: String) throws {
        guard let view = ElementInventory.shared.findElement(byId: elementId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if let scrollView = findParentScrollView(of: view) {
            let frame = view.convert(view.bounds, to: scrollView)
            scrollView.scrollRectToVisible(frame, animated: true)
        }
    }

    // MARK: - Tab switching

    func selectTab(index: Int) throws {
        guard let tabBarController = findTabBarController() else {
            throw InteractionError.noNavigation
        }
        guard index >= 0 && index < (tabBarController.viewControllers?.count ?? 0) else {
            throw InteractionError.elementNotFound("tab_\(index)")
        }
        tabBarController.selectedIndex = index
    }

    // MARK: - Navigation

    func navigateBack() throws {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = scene.keyWindow?.rootViewController else {
            throw InteractionError.noNavigation
        }

        if let nav = findNavigationController(from: rootVC) {
            nav.popViewController(animated: true)
        } else {
            throw InteractionError.noNavigation
        }
    }

    func dismissModal() throws {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = scene.keyWindow?.rootViewController else {
            throw InteractionError.noModal
        }

        let topVC = findTopPresented(from: rootVC)
        guard topVC.presentingViewController != nil else {
            throw InteractionError.noModal
        }
        topVC.dismiss(animated: true)
    }

    // MARK: - Helpers

    private func findFirstScrollView() -> UIScrollView? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else { return nil }
        return findScrollView(in: window)
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView, !(sv is UITextView) { return sv }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    private func findParentScrollView(of view: UIView) -> UIScrollView? {
        var current: UIView? = view.superview
        while let v = current {
            if let sv = v as? UIScrollView { return sv }
            current = v.superview
        }
        return nil
    }

    private func findNavigationController(from vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController { return nav }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return findNavigationController(from: selected)
        }
        if let presented = vc.presentedViewController {
            return findNavigationController(from: presented)
        }
        return vc.navigationController
    }

    private func findTopPresented(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return findTopPresented(from: presented)
        }
        return vc
    }
}

// MARK: - Types

enum ScrollDirection: String, Codable {
    case up, down, left, right

    var isVertical: Bool { self == .up || self == .down }
}

enum InteractionError: LocalizedError {
    case elementNotFound(String)
    case notEditable(String)
    case notScrollable(String)
    case noScrollView
    case noNavigation
    case noModal

    var errorDescription: String? {
        switch self {
        case .elementNotFound(let id): return "Element not found: \(id)"
        case .notEditable(let id): return "Element not editable: \(id)"
        case .notScrollable(let id): return "Element not scrollable: \(id)"
        case .noScrollView: return "No scroll view found"
        case .noNavigation: return "No navigation controller found"
        case .noModal: return "No modal to dismiss"
        }
    }
}

// Helper to find current first responder
extension UIResponder {
    private weak static var _currentFirstResponder: UIResponder?

    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        UIApplication.shared.sendAction(#selector(findFirstResponder(_:)), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }

    @objc private func findFirstResponder(_ sender: Any) {
        UIResponder._currentFirstResponder = self
    }
}

#endif
