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
        if let view = element as? UIView,
           view.isUserInteractionEnabled {
            return view.accessibilityActivate()
        }

        if let accessibilityElement = element as? UIAccessibilityElement {
            return accessibilityElement.accessibilityActivate()
        }

        return false
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
        let count = view.accessibilityElementCount()
        guard count > 0 else { return }

        let resolvedContainerId = view.accessibilityIdentifier ?? containerId

        for index in 0..<count {
            guard let rawElement = view.accessibilityElement(at: index) as? NSObject else { continue }
            if rawElement is UIView { continue }

            let objectId = ObjectIdentifier(rawElement)
            guard visited.insert(objectId).inserted else { continue }
            guard let target = makeTarget(from: rawElement, containerView: view, containerId: resolvedContainerId) else {
                continue
            }
            visitor(target)
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
        let typeName = String(describing: type(of: element))
            .lowercased()
            .replacingOccurrences(of: "ui", with: "")
        return (typeName, "derived")
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
        if let accessibilityElement = element as? UIAccessibilityElement {
            let screenFrame = accessibilityElement.accessibilityFrame
            if !screenFrame.isEmpty {
                return screenFrame
            }

            let containerSpaceFrame = accessibilityElement.accessibilityFrameInContainerSpace
            if !containerSpaceFrame.isEmpty {
                return containerView.convert(containerSpaceFrame, to: nil)
            }
        }

        return .zero
    }

    private func accessibilityIdentifier(for element: NSObject) -> String? {
        if let identified = element as? UIAccessibilityIdentification {
            return identified.accessibilityIdentifier
        }
        return nil
    }

    private func accessibilityLabel(for element: NSObject) -> String? {
        if let accessibilityElement = element as? UIAccessibilityElement {
            return accessibilityElement.accessibilityLabel
        }
        return nil
    }

    private func accessibilityValue(for element: NSObject) -> String? {
        if let accessibilityElement = element as? UIAccessibilityElement {
            return accessibilityElement.accessibilityValue
        }
        return nil
    }

    private func accessibilityTraits(for element: NSObject) -> UIAccessibilityTraits {
        if let accessibilityElement = element as? UIAccessibilityElement {
            return accessibilityElement.accessibilityTraits
        }
        return []
    }

    private func deduplicatedId(_ id: String, seenIds: inout [String: Int]) -> String {
        let count = seenIds[id, default: 0]
        seenIds[id] = count + 1
        return count == 0 ? id : "\(id)_\(count)"
    }
}

#endif

#endif
