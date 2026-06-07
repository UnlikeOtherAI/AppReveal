// iOS accessibility-only element helpers for SwiftUI and UIKit containers

import Foundation

#if os(iOS)

import UIKit

#if DEBUG

@MainActor
struct AccessibilityResolvedTarget {
    let id: String
    let label: String?
    let value: String?
    let frame: CGRect
    let containerId: String?
    let idSource: String
    let element: NSObject
    let containerView: UIView

    var centerPoint: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    func activate() -> Bool {
        // accessibilityActivate() is defined on NSObject via UIKit and works for
        // UIView, UIAccessibilityElement, and SwiftUI virtual accessibility nodes.
        return element.accessibilityActivate()
    }
}

@MainActor
struct TapTargetResolveResult {
    let target: TapTarget?
    let error: String?
    let candidates: [String]?

    var isSuccess: Bool { target != nil }

    init(target: TapTarget) {
        self.target = target
        self.error = nil
        self.candidates = nil
    }

    init(error: String, candidates: [String]? = nil) {
        self.target = nil
        self.error = error
        self.candidates = candidates
    }
}

@MainActor
enum TapTarget {
    case view(UIView)
    case accessibility(AccessibilityResolvedTarget)
    /// Fallback for SwiftUI elements registered via .appReveal() whose frame is known
    /// but that have no backing UIView or UIAccessibilityElement (iOS 26+).
    case point(CGPoint)
}

@MainActor
final class AccessibilityElementInventory {

    static let shared = AccessibilityElementInventory()

    private init() {}

    func appendElements(
        in view: UIView,
        elements: inout [ElementInfo],
        seenIds: inout [String: Int],
        containerId: String?,
        visited: inout Set<ObjectIdentifier>
    ) {
        enumerateElements(in: view, containerId: containerId, visited: &visited) { target in
            let finalId = deduplicatedId(target.id, seenIds: &seenIds)
            let safeAreaInsets = ElementInventory.makeSafeAreaInsets(
                view.safeAreaInsets,
                layoutDirection: view.effectiveUserInterfaceLayoutDirection
            )

            elements.append(
                ElementInfo(
                    id: finalId,
                    type: classifyElement(target.element),
                    label: target.label,
                    value: target.value,
                    enabled: true,
                    visible: !target.frame.isEmpty,
                    tappable: true,
                    frame: ElementInventory.makeFrame(target.frame),
                    safeAreaInsets: safeAreaInsets,
                    safeAreaLayoutGuideFrame: ElementInventory.makeFrame(view.convert(view.safeAreaLayoutGuide.layoutFrame, to: nil)),
                    containerId: containerId,
                    actions: ["tap"],
                    idSource: target.idSource
                )
            )
        }
    }

    func findElement(byListedId id: String, in rootView: UIView) -> AccessibilityResolvedTarget? {
        var seenIds: [String: Int] = [:]
        var visited: Set<ObjectIdentifier> = []
        return findElement(byListedId: id, in: rootView, containerId: nil, seenIds: &seenIds, visited: &visited)
    }

    func findElement(byVisibleText text: String, in rootView: UIView) -> AccessibilityResolvedTarget? {
        var match: AccessibilityResolvedTarget?
        var visited: Set<ObjectIdentifier> = []
        walkContainers(in: rootView, containerId: nil, visited: &visited) { target in
            guard match == nil else { return }
            if target.label == text {
                match = target
            }
        }
        return match
    }

    func collectTextMatches(
        _ text: String,
        matchMode: String,
        in rootView: UIView
    ) -> [AccessibilityResolvedTarget] {
        var matches: [AccessibilityResolvedTarget] = []
        var visited: Set<ObjectIdentifier> = []

        walkContainers(in: rootView, containerId: nil, visited: &visited) { target in
            guard let label = target.label, !label.isEmpty else { return }
            let isMatch: Bool
            switch matchMode {
            case "contains":
                isMatch = label.localizedCaseInsensitiveContains(text)
            default:
                isMatch = label == text
            }
            if isMatch {
                matches.append(target)
            }
        }

        return matches
    }

    func findElement(at point: CGPoint, in rootView: UIView) -> AccessibilityResolvedTarget? {
        var bestMatch: AccessibilityResolvedTarget?
        var bestArea = CGFloat.greatestFiniteMagnitude
        var visited: Set<ObjectIdentifier> = []

        walkContainers(in: rootView, containerId: nil, visited: &visited) { target in
            guard target.frame.contains(point) else { return }
            let area = target.frame.width * target.frame.height
            if area < bestArea {
                bestArea = area
                bestMatch = target
            }
        }

        return bestMatch
    }

    func appendViewTreeNodes(
        for view: UIView,
        depth: Int,
        maxDepth: Int,
        result: inout [[String: Any]],
        visited: inout Set<ObjectIdentifier>
    ) {
        guard depth < maxDepth else { return }

        enumerateElements(in: view, containerId: view.accessibilityIdentifier, visited: &visited) { target in
            var node: [String: Any] = [
                "class": String(describing: type(of: target.element)),
                "frame": "\(Int(target.frame.origin.x)),\(Int(target.frame.origin.y)),\(Int(target.frame.width)),\(Int(target.frame.height))",
                "hidden": target.frame.isEmpty,
                "alpha": 1,
                "userInteraction": true,
                "depth": depth
            ]

            node["accessibilityId"] = target.id
            if let label = target.label, !label.isEmpty {
                node["accessibilityLabel"] = label
            }
            if let value = target.value, !value.isEmpty {
                node["accessibilityValue"] = value
            }
            node["idSource"] = target.idSource
            if let containerId = target.containerId {
                node["containerId"] = containerId
            }
            result.append(node)
        }
    }

    private func findElement(
        byListedId id: String,
        in view: UIView,
        containerId: String?,
        seenIds: inout [String: Int],
        visited: inout Set<ObjectIdentifier>
    ) -> AccessibilityResolvedTarget? {
        var match: AccessibilityResolvedTarget?

        enumerateElements(in: view, containerId: containerId, visited: &visited) { target in
            guard match == nil else { return }
            let finalId = deduplicatedId(target.id, seenIds: &seenIds)
            if finalId == id {
                match = AccessibilityResolvedTarget(
                    id: finalId,
                    label: target.label,
                    value: target.value,
                    frame: target.frame,
                    containerId: target.containerId,
                    idSource: target.idSource,
                    element: target.element,
                    containerView: target.containerView
                )
            }
        }

        guard match == nil else {
            return match
        }

        let currentContainerId = view.accessibilityIdentifier ?? containerId
        for subview in view.subviews where !subview.isHidden {
            if let found = findElement(
                byListedId: id,
                in: subview,
                containerId: currentContainerId,
                seenIds: &seenIds,
                visited: &visited
            ) {
                return found
            }
        }

        return nil
    }

    private func walkContainers(
        in view: UIView,
        containerId: String?,
        visited: inout Set<ObjectIdentifier>,
        visitor: (AccessibilityResolvedTarget) -> Void
    ) {
        enumerateElements(in: view, containerId: containerId, visited: &visited, visitor: visitor)

        let currentContainerId = view.accessibilityIdentifier ?? containerId
        for subview in view.subviews where !subview.isHidden {
            walkContainers(in: subview, containerId: currentContainerId, visited: &visited, visitor: visitor)
        }
    }

    private func enumerateElements(
        in view: UIView,
        containerId: String?,
        visited: inout Set<ObjectIdentifier>,
        visitor: (AccessibilityResolvedTarget) -> Void
    ) {
        let resolvedContainerId = view.accessibilityIdentifier ?? containerId

        // Prefer the modern accessibilityElements array — SwiftUI hosting views use this exclusively.
        // Fall back to the deprecated count/index API for older UIKit patterns.
        let rawElements: [Any]
        if let arr = view.accessibilityElements, !arr.isEmpty {
            rawElements = arr
        } else {
            let count = view.accessibilityElementCount()
            // Guard against NSNotFound (Int.max) and empty containers.
            guard count > 0, count < 100_000 else { return }
            rawElements = (0..<count).compactMap { view.accessibilityElement(at: $0) }
        }

        for element in rawElements {
            guard let rawElement = element as? NSObject else { continue }

            let objectId = ObjectIdentifier(rawElement)
            guard visited.insert(objectId).inserted else { continue }

            // When an accessibility element is itself a UIView (iOS 26+ SwiftUI may do this),
            // recurse into it as a view-level container rather than treating it as a leaf node.
            if let subView = rawElement as? UIView {
                enumerateElements(in: subView, containerId: resolvedContainerId, visited: &visited, visitor: visitor)
                continue
            }

            if let target = makeTarget(from: rawElement, containerView: view, containerId: resolvedContainerId) {
                visitor(target)
            }
            // Recurse into accessibility sub-containers (SwiftUI nests VStack/HStack groups).
            enumerateAccessibilitySubelements(
                of: rawElement,
                containerView: view,
                containerId: resolvedContainerId,
                visited: &visited,
                visitor: visitor
            )
        }
    }

    private func enumerateAccessibilitySubelements(
        of element: NSObject,
        containerView: UIView,
        containerId: String?,
        visited: inout Set<ObjectIdentifier>,
        visitor: (AccessibilityResolvedTarget) -> Void
    ) {
        // SwiftUI virtual accessibility proxy nodes expose children via accessibilityElementCount /
        // accessibilityElement(at:) rather than a KVC-accessible "accessibilityElements" key.
        // Try the array property first; fall back to count/index for SwiftUI nodes.
        let rawArr: [Any]
        if let arr = element.value(forKey: "accessibilityElements") as? [Any], !arr.isEmpty {
            rawArr = arr
        } else {
            let count = element.accessibilityElementCount()
            guard count > 0, count < 100_000 else { return }
            rawArr = (0..<count).compactMap { element.accessibilityElement(at: $0) }
        }
        guard !rawArr.isEmpty else { return }

        let subContainerId = accessibilityIdentifier(for: element) ?? containerId
        for sub in rawArr {
            guard let rawSub = sub as? NSObject, !(rawSub is UIView) else { continue }
            let objectId = ObjectIdentifier(rawSub)
            guard visited.insert(objectId).inserted else { continue }
            if let target = makeTarget(from: rawSub, containerView: containerView, containerId: subContainerId) {
                visitor(target)
            }
            enumerateAccessibilitySubelements(
                of: rawSub,
                containerView: containerView,
                containerId: subContainerId,
                visited: &visited,
                visitor: visitor
            )
        }
    }

    private func makeTarget(
        from element: NSObject,
        containerView: UIView,
        containerId: String?
    ) -> AccessibilityResolvedTarget? {
        let frame = resolvedFrame(for: element, containerView: containerView)
        guard !frame.isEmpty else { return nil }

        let (id, idSource) = resolveId(for: element)
        guard let resolvedId = id else { return nil }

        return AccessibilityResolvedTarget(
            id: resolvedId,
            label: accessibilityLabel(for: element),
            value: accessibilityValue(for: element),
            frame: frame,
            containerId: containerId,
            idSource: idSource,
            element: element,
            containerView: containerView
        )
    }

    private func resolveId(for element: NSObject) -> (String?, String) {
        if let identifier = accessibilityIdentifier(for: element), !identifier.isEmpty {
            return (identifier, "explicit")
        }
        if let label = accessibilityLabel(for: element), !label.isEmpty {
            return (ElementInventory.normalizeToId(label), "semantics")
        }
        // Use trait to derive a human-readable type prefix for unlabeled elements
        // (e.g. SwiftUI image-only buttons with no accessibilityLabel set).
        let traits = accessibilityTraits(for: element)
        if traits.contains(.button) { return ("button", "derived") }
        if traits.contains(.link) { return ("link", "derived") }
        if traits.contains(.header) { return ("header", "derived") }
        if traits.contains(.image) { return ("image", "derived") }
        if traits.contains(.adjustable) { return ("slider", "derived") }
        return ("element", "derived")
    }

    private func classifyElement(_ element: NSObject) -> ElementType {
        let traits = accessibilityTraits(for: element)
        if traits.contains(.button) {
            return .button
        }
        if traits.contains(.link) {
            return .button
        }
        if traits.contains(.header) {
            return .label
        }
        if traits.contains(.image) {
            return .image
        }
        if traits.contains(.adjustable) {
            return .slider
        }
        if traits.contains(.selected) {
            return .cell
        }
        return .other
    }

    private func resolvedFrame(for element: NSObject, containerView: UIView) -> CGRect {
        if let ae = element as? UIAccessibilityElement {
            if !ae.accessibilityFrame.isEmpty { return ae.accessibilityFrame }
            if !ae.accessibilityFrameInContainerSpace.isEmpty {
                return containerView.convert(ae.accessibilityFrameInContainerSpace, to: nil)
            }
        }
        // NSObject UIKit category — works for SwiftUI virtual accessibility nodes.
        let frame = element.accessibilityFrame
        return frame.isEmpty ? .zero : frame
    }

    private func accessibilityIdentifier(for element: NSObject) -> String? {
        if let identified = element as? UIAccessibilityIdentification {
            return identified.accessibilityIdentifier
        }
        // SwiftUI nodes respond to the selector without formally conforming to the protocol.
        if element.responds(to: NSSelectorFromString("accessibilityIdentifier")) {
            return element.value(forKey: "accessibilityIdentifier") as? String
        }
        return nil
    }

    private func accessibilityLabel(for element: NSObject) -> String? {
        // NSObject UIKit category provides accessibilityLabel for all objects including SwiftUI nodes.
        return element.accessibilityLabel
    }

    private func accessibilityValue(for element: NSObject) -> String? {
        return element.accessibilityValue
    }

    private func accessibilityTraits(for element: NSObject) -> UIAccessibilityTraits {
        return element.accessibilityTraits
    }

    private func deduplicatedId(_ id: String, seenIds: inout [String: Int]) -> String {
        let count = seenIds[id, default: 0]
        seenIds[id] = count + 1
        return count == 0 ? id : "\(id)_\(count)"
    }
}

#endif

#endif
