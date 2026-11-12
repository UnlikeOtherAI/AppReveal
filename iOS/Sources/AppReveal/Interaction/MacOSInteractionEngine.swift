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
        if let view = MacOSElementInventory.shared.findElement(byId: elementId, windowId: windowId) {
            if performClick(on: view) {
                return
            }

            if performTableSelection(for: view) {
                return
            }

            let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            if tap(point: view.convert(point, to: nil), windowId: windowId) { return }
            throw InteractionError.notTappable(elementId)
        }

        let windowIds = candidateWindowIds(windowId: windowId)
        guard !windowIds.isEmpty else { throw InteractionError.elementNotFound(elementId) }
        if let entry = SwiftUIElementRegistry.shared.findElement(byId: elementId, windowIds: windowIds) {
            guard entry.enabled else { throw InteractionError.notTappable(elementId) }
            if SwiftUIElementRegistry.shared.activate(id: entry.id) {
                return
            }
            if tap(point: entry.frame.center, windowId: windowId) { return }
            throw InteractionError.notTappable(elementId)
        }

        throw InteractionError.elementNotFound(elementId)
    }

    /// Points use AppKit window coordinates (origin at the bottom left), as in get_elements.
    @discardableResult
    func tap(point: CGPoint, windowId: String? = nil) -> Bool {
        guard point.x.isFinite, point.y.isFinite,
              let window = MacOSWindowProvider.shared.resolve(windowId: windowId)?.nativeWindow,
              let contentView = window.contentView,
              contentView.convert(contentView.bounds, to: nil).contains(point) else {
            return false
        }

        // NSView.hitTest takes coordinates in the receiver's superview, not its bounds.
        let parentPoint = contentView.superview?.convert(point, from: nil) ?? point
        guard let hitView = contentView.hitTest(parentPoint) else { return false }
        if let ref = MacOSWindowProvider.shared.resolve(windowId: windowId),
           let entry = SwiftUIElementRegistry.shared.findTappableElement(at: point, windowIds: [ref.id]),
           SwiftUIElementRegistry.shared.activate(id: entry.id) { return true }
        if performClick(on: hitView) { return true }
        return performTableSelection(for: hitView, windowPoint: point)
    }

    // MARK: - Text

    func type(text: String, elementId: String?, windowId: String? = nil) throws {
        let target = try resolveEditableTarget(elementId: elementId, windowId: windowId)

        let editor = try editableTextView(for: target, id: elementId ?? "current responder")
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    func clear(elementId: String, windowId: String? = nil) throws {
        let target = try resolveEditableTarget(elementId: elementId, windowId: windowId)
        let editor = try editableTextView(for: target, id: elementId)
        editor.insertText("", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    }

    private func editableTextView(for target: AnyObject, id: String) throws -> NSTextView {
        if let field = target as? NSTextField {
            guard field.isEnabled, field.isEditable else { throw InteractionError.notEditable(id) }
            if let editor = field.currentEditor() as? NSTextView { return editor }
            guard field.window?.makeFirstResponder(field) == true,
                  let editor = field.currentEditor() as? NSTextView else {
                throw InteractionError.notEditable(id)
            }
            return editor
        }
        if let editor = target as? NSTextView, editor.isEditable {
            if editor.isFieldEditor, let field = editor.delegate as? NSTextField {
                guard field.isEnabled, field.isEditable else { throw InteractionError.notEditable(id) }
            }
            return editor
        }
        throw InteractionError.notEditable(id)
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

        // AppKit has no generic navigation stack. Siblings in a split view or tabs
        // are not back-stack entries; replacing the window root destroys the app layout.
        _ = root
        throw InteractionError.noNavigation
    }

    func dismissModal(windowId: String? = nil) throws {
        guard let ref = MacOSWindowProvider.shared.resolve(windowId: windowId) else {
            throw InteractionError.noModal
        }

        if let parent = ref.nativeWindow.sheetParent {
            parent.endSheet(ref.nativeWindow)
            return
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
        guard !view.isHiddenOrHasHiddenAncestor else { return false }
        if let control = findAncestor(of: view, matching: { candidate in
            candidate is NSControl && !(candidate is NSTableView) &&
                !((candidate as? NSTextField).map { !$0.isEditable } ?? false)
        }) as? NSControl {
            guard control.isEnabled else { return false }
            if let field = control as? NSTextField {
                return field.window?.makeFirstResponder(field) == true
            }
            if let toggle = control as? NSSwitch {
                toggle.state = toggle.state == .on ? .off : .on
                _ = toggle.sendAction(toggle.action, to: toggle.target)
                return true
            }
            if let button = control as? NSButton {
                button.performClick(nil)
                return true
            }
            // Generic NSControl.performClick can silently do nothing (sliders, tables).
            return control.accessibilityPerformPress()
        }
        return false
    }

    private func performTableSelection(for view: NSView, windowPoint: CGPoint? = nil) -> Bool {
        guard let tableView = findAncestorTableView(from: view), tableView.isEnabled else { return false }
        let row: Int
        if let point = windowPoint {
            row = tableView.row(at: tableView.convert(point, from: nil))
        } else {
            row = tableView.row(for: view)
        }
        guard row >= 0, row < tableView.numberOfRows,
              tableView.delegate?.tableView?(tableView, shouldSelectRow: row) != false else { return false }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        guard tableView.selectedRowIndexes.contains(row) else { return false }
        tableView.scrollRowToVisible(row)
        if let action = tableView.action {
            NSApp.sendAction(action, to: tableView.target, from: tableView)
        }
        // selectRowIndexes posts the selection notification itself. Calling the delegate
        // again duplicates navigation and any side effects attached to selection.
        return true
    }

    private func resolveEditableTarget(elementId: String?, windowId: String?) throws -> AnyObject {
        if let id = elementId {
            if let target = MacOSElementInventory.shared.findElement(byId: id, windowId: windowId) { return target }
            if let ref = MacOSWindowProvider.shared.resolve(windowId: windowId),
               let contentView = ref.contentView,
               let entry = SwiftUIElementRegistry.shared.findElement(byId: id, windowIds: [ref.id]),
               entry.enabled, entry.type == .textField,
               let target = findEditableView(in: contentView, at: entry.frame.center) {
                return target
            }
            throw InteractionError.elementNotFound(id)
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

    private func findEditableView(in view: NSView, at windowPoint: CGPoint) -> NSView? {
        guard !view.isHiddenOrHasHiddenAncestor,
              view.convert(view.bounds, to: nil).contains(windowPoint) else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.isEnabled { return field }
        if let editor = view as? NSTextView, editor.isEditable { return editor }
        for child in view.subviews {
            if let target = findEditableView(in: child, at: windowPoint) { return target }
        }
        return nil
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

    private func candidateWindowIds(windowId: String?) -> Set<String> {
        if let ref = MacOSWindowProvider.shared.resolve(windowId: windowId) {
            return Set([ref.id])
        }
        return windowId == nil ? Set(MacOSWindowProvider.shared.allWindows().map(\.id)) : []
    }
}

#endif // os(macOS)
#endif // DEBUG
