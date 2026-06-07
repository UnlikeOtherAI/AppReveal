// Executes UI interactions (tap, type, scroll, navigate)

import Foundation

#if DEBUG

// MARK: - Types (cross-platform)

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

#if os(iOS)

import UIKit

let appRevealTapPointNotificationName = Notification.Name("appreveal.interaction.tap_point")
let appRevealTapPointUserInfoKey = "point"

@MainActor
final class InteractionEngine {

    static let shared = InteractionEngine()

    private init() {}

    // MARK: - Tap

    func tap(elementId: String, windowId: String? = nil) throws {
        guard let target = ElementInventory.shared.findTapTarget(byId: elementId, windowId: windowId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if !performTap(on: target, windowId: windowId) {
            throw InteractionError.elementNotFound(elementId)
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

    @discardableResult
    func tap(point: CGPoint, windowId: String? = nil) -> Bool {
        postTapPoint(point)

        for ref in candidateWindows(windowId: windowId) {
            let window = ref.nativeWindow
            let hitView = window.hitTest(point, with: nil)

            // Check if tapping inside a tab bar
            if let tabBar = findParent(of: hitView, type: UITabBar.self),
               let tabBarController = findTabBarController(windowId: ref.id) {
                let localPoint = tabBar.convert(point, from: window)
                if let items = tabBar.items {
                    let itemWidth = tabBar.bounds.width / CGFloat(items.count)
                    let index = Int(localPoint.x / itemWidth)
                    if index >= 0 && index < items.count {
                        tabBarController.selectedIndex = index
                        return true
                    }
                }
            }

            // SwiftUI hosting views need a dedicated tap path. On iOS 26+ SwiftUI moved all
            // touch handling into UIKit's window-level event dispatch, so direct touchesBegan
            // calls are ignored. We try accessibilityActivate() first (SwiftUI Button
            // implements this to fire its action, works without VoiceOver) and fall back to
            // IOHIDEvent injection via UIApplication._handleHIDEvent: on iOS 26+, then KVC
            // touch injection on older OS.
            let isSwiftUIHost = hitView.map { Self.isSwiftUIHostingView($0) } ?? false

            if isSwiftUIHost, let hostingView = hitView {
                let axTarget = AccessibilityElementInventory.shared.findElement(at: point, in: window)
                if let accessibilityTarget = axTarget, accessibilityTarget.activate() {
                    return true
                }
                Self.deliverSyntheticTap(at: point, to: hostingView)
                return true
            }

            if !isSwiftUIHost, let hitView, performTap(on: .view(hitView), windowId: ref.id, postPoint: false) {
                return true
            }

            if let accessibilityTarget = AccessibilityElementInventory.shared.findElement(at: point, in: window),
               performTap(on: .accessibility(accessibilityTarget), windowId: ref.id, postPoint: false) {
                return true
            }
        }
        return false
    }

    private func postTapPoint(_ point: CGPoint) {
        NotificationCenter.default.post(
            name: appRevealTapPointNotificationName,
            object: nil,
            userInfo: [appRevealTapPointUserInfoKey: NSValue(cgPoint: point)]
        )
    }

    private func fireTapGestureRecognizers(on view: UIView?, at point: CGPoint) -> Bool {
        var current = view
        while let v = current {
            if let recognizers = v.gestureRecognizers {
                for recognizer in recognizers where recognizer is UITapGestureRecognizer && recognizer.isEnabled {
                    if let targets = recognizer.value(forKey: "_targets") as? [NSObject] {
                        for target in targets {
                            let description = String(describing: target)
                            if description.contains("action=") {
                                recognizer.state = .ended
                                return true
                            }
                        }
                    }
                }
            }
            current = v.superview
        }
        return false
    }

    private func findTabBarController(windowId: String? = nil) -> UITabBarController? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let root = ref.rootViewController else { return nil }
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

    private static func isSwiftUIHostingView(_ view: UIView) -> Bool {
        // On iOS 26+ Swift.type(of:).description() returns the ObjC mangled name
        // (e.g. `_TtGC7SwiftUI14_UIHostingView…`) rather than the Swift qualified name,
        // so check with contains rather than hasPrefix on a stripped base component.
        let name = Swift.type(of: view).description()
        return name.contains("_UIHostingView") || name.contains("UIHostingView")
    }

    // Delivers a tap to a SwiftUI hosting view.
    //
    // On iOS 26+, SwiftUI's gesture engine runs entirely inside UIKit's window-level event
    // dispatch. Direct touchesBegan/touchesEnded calls on _UIHostingView are ignored. We
    // synthesise a real IOHIDDigitizerEvent (hand + finger) and inject it via the private
    // UIApplication._enqueueHIDEvent: after binding the window's context ID via
    // BKSHIDEventSetDigitizerInfo. This mirrors what Lyft's Hammer library does and works in
    // both Simulator and on device. Private APIs are intentional — AppReveal is debug-only.
    //
    // On iOS < 26 the touchesBegan/touchesEnded path works because _UIHostingView overrode
    // those methods on earlier OS versions.
    private static func deliverSyntheticTap(at windowPoint: CGPoint, to view: UIView) {
        guard let window = view.window else { return }
        if #available(iOS 26, *) {
            if hidEventTap(at: windowPoint, in: window) { return }
        }
        kvcTouchTap(at: windowPoint, to: view, window: window)
    }

    // iOS 26+: synthesise a proper IOHIDDigitizerEvent with a hand parent event and a
    // finger sub-event, bind it to the target window via BKSHIDEventSetDigitizerInfo, and
    // inject it into UIKit's HID pipeline via UIApplication._enqueueHIDEvent:.
    //
    // Coordinates are absolute screen points (not normalised 0–1).
    // Event-mask values: range=0x1, touch=0x2, position=0x4.
    // Parent hand mask = child masks ∩ {touch, attribute} → 0x2 for a single finger tap.
    @available(iOS 26, *)
    private static func hidEventTap(at windowPoint: CGPoint, in window: UIWindow) -> Bool {
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        let bbs = dlopen(
            "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
            RTLD_NOW)
        let rtld = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT

        guard
            let mkDigitizerSym = dlsym(iokit, "IOHIDEventCreateDigitizerEvent"),
            let mkFingerSym    = dlsym(iokit, "IOHIDEventCreateDigitizerFingerEvent"),
            let appendSym      = dlsym(iokit, "IOHIDEventAppendEvent"),
            let setIntSym      = dlsym(iokit, "IOHIDEventSetIntegerValue"),
            let setFloatSym    = dlsym(iokit, "IOHIDEventSetFloatValue"),
            let setSenderSym   = dlsym(iokit, "IOHIDEventSetSenderID"),
            let bksSym         = dlsym(bbs,   "BKSHIDEventSetDigitizerInfo"),
            let msgSendSym     = dlsym(rtld,   "objc_msgSend")
        else { return false }

        typealias MkDigitizerFn = @convention(c) (
            CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
            CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, Bool, CFOptionFlags
        ) -> AnyObject
        typealias MkFingerFn = @convention(c) (
            CFAllocator?, UInt64, UInt32, UInt32, UInt32,
            CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, Bool, CFOptionFlags
        ) -> AnyObject
        typealias AppendFn    = @convention(c) (AnyObject, AnyObject, CFOptionFlags) -> Void
        typealias SetIntFn    = @convention(c) (AnyObject, UInt32, Int) -> Void
        typealias SetFloatFn  = @convention(c) (AnyObject, UInt32, CGFloat) -> Void
        typealias SetSenderFn = @convention(c) (AnyObject, UInt64) -> Void
        typealias BKSFn       = @convention(c) (AnyObject, UInt32, Bool, Bool, CFString?, CFTimeInterval, Float) -> Void
        typealias MsgSendU32  = @convention(c) (AnyObject, Selector) -> UInt32

        let mkDigitizer = unsafeBitCast(mkDigitizerSym, to: MkDigitizerFn.self)
        let mkFinger = unsafeBitCast(mkFingerSym, to: MkFingerFn.self)
        let appendFn = unsafeBitCast(appendSym, to: AppendFn.self)
        let setIntFn = unsafeBitCast(setIntSym, to: SetIntFn.self)
        let setFloatFn = unsafeBitCast(setFloatSym, to: SetFloatFn.self)
        let setSenderFn = unsafeBitCast(setSenderSym, to: SetSenderFn.self)
        let bksFn = unsafeBitCast(bksSym, to: BKSFn.self)
        let msgSendU32 = unsafeBitCast(msgSendSym, to: MsgSendU32.self)

        let contextId = msgSendU32(window, NSSelectorFromString("_contextId"))

        let enqueueHIDSel = NSSelectorFromString("_enqueueHIDEvent:")
        guard UIApplication.shared.responds(to: enqueueHIDSel) else { return false }

        // finger eventMask: touch(0x2)|range(0x1) = 0x3 for both began and ended
        // parent hand eventMask: finger masks ∩ {touch(0x2), attribute(0x40)} = 0x2
        let fingerMask: UInt32 = 0x3
        let handMask:   UInt32 = 0x2
        let senderId:   UInt64 = 0x0000000123456789

        func makeEvent(at time: UInt64, touching: Bool) -> AnyObject {
            let hand = mkDigitizer(
                nil, time,
                3, 0, 0,        // transducerType=hand, index=0, identifier=0
                handMask, 0,    // eventMask, buttonEvent
                0, 0, 0, 0, 0,  // x, y, z, pressure, twist (unused on parent)
                false, touching,
                0)
            setIntFn(hand, 0xB0019, 1)      // isDisplayIntegrated = 1
            setSenderFn(hand, senderId)

            let finger = mkFinger(
                nil, time,
                1, 1,           // identifier=1, fingerIndex=1 (rightThumb)
                fingerMask,
                windowPoint.x, windowPoint.y, 0,  // absolute screen coordinates
                0, 0,           // pressure, twist
                touching, touching,
                0)
            setFloatFn(finger, 0xB0014, 5)  // majorRadius
            setFloatFn(finger, 0xB0015, 5)  // minorRadius
            appendFn(hand, finger, 0)
            return hand
        }

        let beganEvent = makeEvent(at: mach_absolute_time(), touching: true)
        bksFn(beganEvent, contextId, false, false, nil, 0, 0)
        UIApplication.shared.perform(enqueueHIDSel, with: beganEvent)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let endedEvent = makeEvent(at: mach_absolute_time(), touching: false)
            bksFn(endedEvent, contextId, false, false, nil, 0, 0)
            UIApplication.shared.perform(enqueueHIDSel, with: endedEvent)
        }
        return true
    }

    // Fallback for iOS < 26: synthesise a UITouch via KVC and deliver via
    // touchesBegan/touchesEnded (SwiftUI overrode these on pre-iOS 26).
    private static func kvcTouchTap(at windowPoint: CGPoint, to view: UIView, window: UIWindow) {
        let knownIvars: Set<String> = {
            var count: UInt32 = 0
            guard let list = class_copyIvarList(UITouch.self, &count) else { return [] }
            defer { free(list) }
            var names = Set<String>()
            for i in 0..<Int(count) { if let n = ivar_getName(list[i]) { names.insert(String(cString: n)) } }
            return names
        }()

        let touch = UITouch()
        touch.setValue(window, forKey: "_window")
        for ivar in ["_responder", "_cachedResponderView", "_view"] where knownIvars.contains(ivar) {
            touch.setValue(view, forKey: ivar)
        }
        touch.setValue(NSValue(cgPoint: windowPoint), forKey: "_locationInWindow")
        touch.setValue(NSValue(cgPoint: windowPoint), forKey: "_previousLocationInWindow")
        touch.setValue(1, forKey: "_tapCount")
        touch.setValue(CACurrentMediaTime(), forKey: "_timestamp")

        let touches: Set<UITouch> = [touch]
        touch.setValue(UITouch.Phase.began.rawValue, forKey: "_phase")
        view.touchesBegan(touches, with: nil)
        DispatchQueue.main.async {
            touch.setValue(UITouch.Phase.ended.rawValue, forKey: "_phase")
            view.touchesEnded(touches, with: nil)
        }
    }

    private func performTap(
        on target: TapTarget,
        windowId: String?,
        postPoint: Bool = true
    ) -> Bool {
        switch target {
        case .view(let view):
            let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            if postPoint {
                postTapPoint(point)
            }
            return performTap(onView: view, at: point)
        case .accessibility(let accessibilityTarget):
            if postPoint {
                postTapPoint(accessibilityTarget.centerPoint)
            }
            if accessibilityTarget.activate() {
                return true
            }
            guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
                return false
            }
            let hitView = ref.nativeWindow.hitTest(accessibilityTarget.centerPoint, with: nil)
            return performTap(onView: hitView, at: accessibilityTarget.centerPoint)
        }
    }

    private func performTap(onView view: UIView?, at point: CGPoint) -> Bool {
        guard let view else { return false }

        if let control = findAncestorControl(from: view) {
            control.sendActions(for: .touchUpInside)
            return true
        }

        if let cell = findParent(of: view, type: UITableViewCell.self),
           let tableView = findParentTableView(of: cell),
           let indexPath = tableView.indexPath(for: cell) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            tableView.delegate?.tableView?(tableView, didSelectRowAt: indexPath)
            return true
        }

        if let cell = findParent(of: view, type: UICollectionViewCell.self),
           let collectionView = findParentCollectionView(of: cell),
           let indexPath = collectionView.indexPath(for: cell) {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
            return true
        }

        return fireTapGestureRecognizers(on: view, at: point)
    }

    private func findAncestorControl(from view: UIView) -> UIControl? {
        var current: UIView? = view
        while let candidate = current {
            if let control = candidate as? UIControl {
                return control
            }
            current = candidate.superview
        }
        return nil
    }

    // MARK: - Text

    func type(text: String, elementId: String?, windowId: String? = nil) throws {
        let target = try resolveEditableTarget(elementId: elementId, windowId: windowId)

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

    func clear(elementId: String, windowId: String? = nil) throws {
        let view = try resolveEditableTarget(elementId: elementId, windowId: windowId)

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

    func scroll(direction: ScrollDirection, containerId: String?, windowId: String? = nil) throws {
        let scrollView: UIScrollView

        if let id = containerId {
            guard let view = ElementInventory.shared.findElement(byId: id, windowId: windowId) as? UIScrollView else {
                throw InteractionError.notScrollable(id)
            }
            scrollView = view
        } else {
            guard let found = findFirstScrollView(windowId: windowId) else {
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

    func scrollTo(elementId: String, windowId: String? = nil) throws {
        guard let view = ElementInventory.shared.findElement(byId: elementId, windowId: windowId) else {
            throw InteractionError.elementNotFound(elementId)
        }

        if let scrollView = findParentScrollView(of: view) {
            let frame = view.convert(view.bounds, to: scrollView)
            scrollView.scrollRectToVisible(frame, animated: true)
        }
    }

    // MARK: - Tab switching

    func selectTab(index: Int, windowId: String? = nil) throws {
        guard let tabBarController = findTabBarController(windowId: windowId) else {
            throw InteractionError.noNavigation
        }
        guard index >= 0 && index < (tabBarController.viewControllers?.count ?? 0) else {
            throw InteractionError.elementNotFound("tab_\(index)")
        }
        tabBarController.selectedIndex = index
    }

    // MARK: - Navigation

    func navigateBack(windowId: String? = nil) throws {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let rootVC = ref.rootViewController else {
            throw InteractionError.noNavigation
        }

        if let nav = findNavigationController(from: rootVC) {
            nav.popViewController(animated: true)
        } else {
            throw InteractionError.noNavigation
        }
    }

    func dismissModal(windowId: String? = nil) throws {
        guard let ref = platformWindowProvider.resolve(windowId: windowId),
              let rootVC = ref.rootViewController else {
            throw InteractionError.noModal
        }

        let topVC = findTopPresented(from: rootVC)
        guard topVC.presentingViewController != nil else {
            if let fallbackModal = findVisiblePresentedControllers(from: rootVC).last {
                fallbackModal.dismiss(animated: true)
                return
            }
            throw InteractionError.noModal
        }
        topVC.dismiss(animated: true)
    }

    // MARK: - Helpers

    private func findFirstScrollView(windowId: String? = nil) -> UIScrollView? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else { return nil }
        return findScrollView(in: ref.nativeWindow)
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

    private func findVisiblePresentedControllers(from root: UIViewController) -> [UIViewController] {
        var results: [UIViewController] = []
        var visited: Set<ObjectIdentifier> = []

        func walk(_ vc: UIViewController) {
            let identifier = ObjectIdentifier(vc)
            guard visited.insert(identifier).inserted else { return }

            if vc !== root,
               vc.viewIfLoaded?.window != nil,
               vc.presentingViewController != nil || vc.presentationController?.presentingViewController != nil {
                results.append(vc)
            }

            if let presented = vc.presentedViewController {
                walk(presented)
            }
            if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
                walk(visible)
            }
            if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
                walk(selected)
            }
            for child in vc.children {
                walk(child)
            }
        }

        walk(root)
        return results
    }

    private func resolveEditableTarget(elementId: String?, windowId: String?) throws -> UIView {
        if let elementId {
            if let view = editableView(forElementId: elementId, windowId: windowId) {
                return view
            }
            throw InteractionError.elementNotFound(elementId)
        }

        if let responder = currentEditableResponder(windowId: windowId) {
            return responder
        }

        throw InteractionError.notEditable("current responder")
    }

    private func editableView(forElementId elementId: String, windowId: String?) -> UIView? {
        if let view = ElementInventory.shared.findElement(byId: elementId, windowId: windowId),
           let editable = editableAncestor(for: view) {
            return editable
        }

        guard let target = ElementInventory.shared.findTapTarget(byId: elementId, windowId: windowId) else {
            return nil
        }

        switch target {
        case .view(let view):
            return editableAncestor(for: view)
        case .accessibility(let accessibilityTarget):
            if let hitView = hitView(at: accessibilityTarget.centerPoint, windowId: windowId, preferredWindow: accessibilityTarget.containerView.window) {
                return editableAncestor(for: hitView)
            }
            return nil
        }
    }

    private func currentEditableResponder(windowId: String?) -> UIView? {
        if let responder = UIResponder.currentFirstResponder as? UIView,
           let editable = editableAncestor(for: responder) {
            return editable
        }

        for ref in candidateWindows(windowId: windowId) {
            if let responder = firstResponder(in: ref.nativeWindow),
               let editable = editableAncestor(for: responder) {
                return editable
            }
        }

        return nil
    }

    private func hitView(at point: CGPoint, windowId: String?, preferredWindow: UIWindow?) -> UIView? {
        if let preferredWindow,
           let hitView = preferredWindow.hitTest(point, with: nil) {
            return hitView
        }

        for ref in candidateWindows(windowId: windowId) {
            if let hitView = ref.nativeWindow.hitTest(point, with: nil) {
                return hitView
            }
        }

        return nil
    }

    private func editableAncestor(for view: UIView?) -> UIView? {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView {
                return candidate
            }
            current = candidate.superview
        }
        return nil
    }

    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder {
            return view
        }
        for subview in view.subviews {
            if let responder = firstResponder(in: subview) {
                return responder
            }
        }
        return nil
    }

    private func candidateWindows(windowId: String?) -> [WindowRef] {
        IOSWindowProvider.shared.windowsForInteraction(windowId: windowId)
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

#endif // os(iOS)

#endif // DEBUG
