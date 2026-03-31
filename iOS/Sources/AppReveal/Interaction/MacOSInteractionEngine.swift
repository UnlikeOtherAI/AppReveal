// Executes macOS AppKit interactions (tap, type, scroll, navigate)

import Foundation

#if DEBUG
#if os(macOS)

import AppKit

private typealias MacOSElementInventory = ElementInventory
typealias InteractionEngine = MacOSInteractionEngine

@MainActor
final class MacOSInteractionEngine {

    static let shared = MacOSInteractionEngine()

    private init() {}

    // MARK: - Tap

    func tap(elementId: String, windowId: String? = nil) throws {
        guard let view = MacOSElementInventory.shared.findElement(byId: elementId, windowId: windowId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if performClick(on: view) {
            return
        }

        if performTableSelection(for: view) {
            return
        }

        let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        tap(point: view.convert(point, to: nil), windowId: windowId)
    }

    func tap(point: CGPoint, windowId: String? = nil) {
        guard let window = MacOSWindowProvider.shared.resolve(windowId: windowId)?.nativeWindow,
              let contentView = window.contentView else {
            return
        }

        let localPoint = contentView.convert(point, from: nil)
        guard let hitView = contentView.hitTest(localPoint) else { return }

        if performClick(on: hitView) {
            return
        }

        _ = performTableSelection(for: hitView)
    }

    // MARK: - Text

    func type(text: String, elementId: String?, windowId: String? = nil) throws {
        let target = try resolveEditableTarget(elementId: elementId, windowId: windowId)

        if let textField = target as? NSTextField {
            textField.stringValue += text
            textField.currentEditor()?.selectedRange = NSRange(location: textField.stringValue.count, length: 0)
            textField.sendAction(textField.action, to: textField.target)
            return
        }

        if let textView = target as? NSTextView {
            textView.insertText(text, replacementRange: textView.selectedRange())
            return
        }

        throw InteractionError.notEditable(elementId ?? "current responder")
    }

    func clear(elementId: String, windowId: String? = nil) throws {
        guard let view = MacOSElementInventory.shared.findElement(byId: elementId, windowId: windowId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if let textField = view as? NSTextField {
            textField.stringValue = ""
            textField.currentEditor()?.string = ""
            textField.sendAction(textField.action, to: textField.target)
            return
        }

        if let textView = view as? NSTextView {
            textView.string = ""
            return
        }

        throw InteractionError.notEditable(elementId)
    }

    // MARK: - Scroll

    func scroll(direction: ScrollDirection, containerId: String?, windowId: String? = nil) throws {
        let scrollView: NSScrollView

        if let id = containerId {
            guard let view = MacOSElementInventory.shared.findElement(byId: id, windowId: windowId) as? NSScrollView else {
                throw InteractionError.notScrollable(id)
            }
            scrollView = view
        } else {
            guard let found = findFirstScrollView(windowId: windowId) else {
                throw InteractionError.noScrollView
            }
            scrollView = found
        }

        guard let documentView = scrollView.documentView else {
            throw InteractionError.notScrollable(containerId ?? "default")
        }

        let clipView = scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let pageSize = direction.isVertical ? visibleRect.height : visibleRect.width
        let step = pageSize * 0.8
        let maxX = max(documentView.bounds.width - visibleRect.width, 0)
        let maxY = max(documentView.bounds.height - visibleRect.height, 0)
        var origin = visibleRect.origin

        switch direction {
        case .up:
            origin.y = documentView.isFlipped
                ? max(origin.y - step, 0)
                : min(origin.y + step, maxY)
        case .down:
            origin.y = documentView.isFlipped
                ? min(origin.y + step, maxY)
                : max(origin.y - step, 0)
        case .left:
            origin.x = max(origin.x - step, 0)
        case .right:
            origin.x = min(origin.x + step, maxX)
        }

        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func scrollTo(elementId: String, windowId: String? = nil) throws {
        guard let view = MacOSElementInventory.shared.findElement(byId: elementId, windowId: windowId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        view.scrollToVisible(view.bounds)
    }

    // MARK: - Tab switching

    func selectTab(index: Int, windowId: String? = nil) throws {
        guard let root = MacOSWindowProvider.shared.resolve(windowId: windowId)?.rootViewController,
              let tabController = findTabViewController(from: root) else {
            throw InteractionError.noNavigation
        }

        guard index >= 0 && index < tabController.tabViewItems.count else {
            throw InteractionError.elementNotFound("tab_\(index)")
        }

        tabController.selectedTabViewItemIndex = index
    }

    // MARK: - Navigation

    func navigateBack(windowId: String? = nil) throws {
        guard let ref = MacOSWindowProvider.shared.resolve(windowId: windowId),
              let root = ref.rootViewController else {
            throw InteractionError.noNavigation
        }

        var current = findTopViewController(from: root)

        while let parent = current.parent {
            if let tabController = parent as? NSTabViewController,
               let currentIndex = tabController.children.firstIndex(where: { $0 === current }),
               currentIndex > 0 {
                tabController.selectedTabViewItemIndex = currentIndex - 1
                return
            }

            if let currentIndex = parent.children.firstIndex(where: { $0 === current }),
               currentIndex > 0 {
                ref.nativeWindow.contentViewController = parent.children[currentIndex - 1]
                return
            }

            current = parent
        }

        throw InteractionError.noNavigation
    }

    func dismissModal(windowId: String? = nil) throws {
        guard let ref = MacOSWindowProvider.shared.resolve(windowId: windowId) else {
            throw InteractionError.noModal
        }

        if let sheet = ref.nativeWindow.attachedSheet {
            ref.nativeWindow.endSheet(sheet)
            return
        }

        guard let root = ref.rootViewController,
              let presented = findPresentedViewController(from: root) else {
            throw InteractionError.noModal
        }

        presented.dismiss(nil)
    }

    // MARK: - Helpers

    private func performClick(on view: NSView) -> Bool {
        if let button = findAncestor(of: view, matching: { $0 is NSButton }) as? NSButton {
            button.performClick(nil)
            return true
        }

        if let control = findAncestor(of: view, matching: { $0 is NSControl }) as? NSControl {
            control.performClick(nil)
            return true
        }

        return false
    }

    private func performTableSelection(for view: NSView) -> Bool {
        guard let tableView = findAncestorTableView(from: view) else {
            return false
        }

        let row = tableView === view ? tableView.selectedRow : tableView.row(for: view)
        guard row >= 0 else { return false }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        if let action = tableView.action {
            NSApp.sendAction(action, to: tableView.target, from: tableView)
        }
        tableView.delegate?.tableViewSelectionDidChange?(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))
        return true
    }

    private func resolveEditableTarget(elementId: String?, windowId: String?) throws -> AnyObject {
        if let id = elementId {
            guard let target = MacOSElementInventory.shared.findElement(byId: id, windowId: windowId) else {
                throw InteractionError.elementNotFound(id)
            }
            return target
        }

        guard let window = MacOSWindowProvider.shared.resolve(windowId: windowId)?.nativeWindow else {
            throw InteractionError.notEditable("current responder")
        }

        if let textView = window.firstResponder as? NSTextView {
            return textView
        }

        if let view = window.firstResponder as? NSView {
            return view
        }

        throw InteractionError.notEditable("current responder")
    }

    private func findFirstScrollView(windowId: String?) -> NSScrollView? {
        guard let contentView = MacOSWindowProvider.shared.resolve(windowId: windowId)?.contentView else {
            return nil
        }
        return findScrollView(in: contentView)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView,
           !(scrollView.documentView is NSTextView) {
            return scrollView
        }

        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }

        return nil
    }

    private func findTabViewController(from viewController: NSViewController) -> NSTabViewController? {
        if let tabController = viewController as? NSTabViewController {
            return tabController
        }

        if let presented = viewController.presentedViewControllers {
            for child in presented {
                if let found = findTabViewController(from: child) {
                    return found
                }
            }
        }

        for child in viewController.children {
            if let found = findTabViewController(from: child) {
                return found
            }
        }

        return nil
    }

    private func findTopViewController(from viewController: NSViewController) -> NSViewController {
        if let presented = viewController.presentedViewControllers,
           let last = presented.last {
            return findTopViewController(from: last)
        }

        if let tabController = viewController as? NSTabViewController,
           tabController.selectedTabViewItemIndex >= 0,
           tabController.selectedTabViewItemIndex < tabController.children.count {
            return findTopViewController(from: tabController.children[tabController.selectedTabViewItemIndex])
        }

        if let lastChild = viewController.children.last {
            return findTopViewController(from: lastChild)
        }

        return viewController
    }

    private func findPresentedViewController(from viewController: NSViewController) -> NSViewController? {
        guard let presented = viewController.presentedViewControllers,
              let last = presented.last else {
            return nil
        }

        return findPresentedViewController(from: last) ?? last
    }

    private func findAncestor(of view: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
        var current: NSView? = view
        while let candidate = current {
            if predicate(candidate) {
                return candidate
            }
            current = candidate.superview
        }
        return nil
    }

    private func findAncestorTableView(from view: NSView) -> NSTableView? {
        findAncestor(of: view, matching: { $0 is NSTableView }) as? NSTableView
    }
}

#endif // os(macOS)
#endif // DEBUG
