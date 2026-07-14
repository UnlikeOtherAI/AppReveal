// OCR fallback for SwiftUI text rendered without UIKit/accessibility nodes.

import Foundation

#if os(iOS)

import UIKit
import Vision

#if DEBUG

@MainActor
struct OCRTextTarget {
    let text: String
    let frame: CGRect
    let windowId: String

    var centerPoint: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

@MainActor
final class OCRTextInventory {

    static let shared = OCRTextInventory()

    private init() {}

    func textTargets(windowId: String? = nil) -> [OCRTextTarget] {
        IOSWindowProvider.shared.windowsForInteraction(windowId: windowId)
            .flatMap { targets(in: $0) }
            .sorted { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 4 {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return lhs.frame.minX < rhs.frame.minX
            }
    }

    func findTextTarget(
        _ text: String,
        matchMode: String = "exact",
        occurrence: Int = 0,
        windowId: String? = nil
    ) -> OCRTextTarget? {
        let matches = matchingTextTargets(text, matchMode: matchMode, windowId: windowId)
        guard !matches.isEmpty else { return nil }
        let index = matches.count == 1 ? 0 : max(0, occurrence)
        guard index < matches.count else { return nil }
        return matches[index]
    }

    func matchingTextTargets(
        _ text: String,
        matchMode: String = "exact",
        windowId: String? = nil
    ) -> [OCRTextTarget] {
        textTargets(windowId: windowId).filter { target in
            Self.matches(target.text, query: text, matchMode: matchMode)
        }
    }

    func findElementIdFallback(_ elementId: String, windowId: String? = nil) -> OCRTextTarget? {
        let targets = textTargets(windowId: windowId)
        guard !targets.isEmpty else { return nil }

        for candidate in Self.textCandidates(forElementId: elementId) {
            if let exact = targets.first(where: { Self.matches($0.text, query: candidate, matchMode: "exact") }) {
                return exact
            }
        }

        for candidate in Self.textCandidates(forElementId: elementId).filter({ Self.normalized($0).count >= 4 }) {
            if let contains = targets.first(where: { Self.matches($0.text, query: candidate, matchMode: "contains") }) {
                return contains
            }
        }

        return nil
    }

    static func normalized(_ text: String) -> String {
        let scalarView = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(scalar)
                : " "
        }
        return String(scalarView)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func textCandidates(forElementId elementId: String) -> [String] {
        let tokens = splitIdentifierIntoWords(elementId)
        guard !tokens.isEmpty else { return [elementId] }

        var candidates: [String] = []
        func append(_ value: String) {
            let normalizedValue = normalized(value)
            guard !normalizedValue.isEmpty else { return }
            if !candidates.contains(normalizedValue) {
                candidates.append(normalizedValue)
            }
        }

        append(elementId)

        let separators = CharacterSet(charactersIn: "./:-")
        if let lastSegment = elementId.components(separatedBy: separators).last {
            append(lastSegment)
            append(splitIdentifierIntoWords(lastSegment).joined(separator: " "))
        }

        for start in tokens.indices {
            let suffix = tokens[start...].joined(separator: " ")
            append(suffix)
        }

        if let last = tokens.last {
            append(last)
        }

        return candidates
    }

    private func targets(in windowRef: WindowRef) -> [OCRTextTarget] {
        let window = windowRef.nativeWindow
        let hostingFrames = swiftUIHostingFrames(in: window)
        guard !hostingFrames.isEmpty else { return [] }
        guard let image = captureImage(in: window), let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let windowBounds = window.bounds
        return (request.results ?? []).compactMap { observation in
            guard let recognized = observation.topCandidates(1).first else { return nil }
            let text = recognized.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let box = observation.boundingBox
            let frame = CGRect(
                x: box.minX * windowBounds.width,
                y: (1 - box.maxY) * windowBounds.height,
                width: box.width * windowBounds.width,
                height: box.height * windowBounds.height
            )
            guard !frame.isEmpty else { return nil }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard hostingFrames.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(center) }) else {
                return nil
            }

            return OCRTextTarget(text: text, frame: frame, windowId: windowRef.id)
        }
    }

    private func captureImage(in window: UIWindow) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    private func swiftUIHostingFrames(in root: UIView) -> [CGRect] {
        var frames: [CGRect] = []
        collectSwiftUIHostingFrames(in: root, frames: &frames)
        return frames
    }

    private func collectSwiftUIHostingFrames(in view: UIView, frames: inout [CGRect]) {
        if Self.isSwiftUIHostingView(view) {
            frames.append(view.convert(view.bounds, to: nil))
        }
        for subview in view.subviews where !subview.isHidden && subview.alpha > 0 {
            collectSwiftUIHostingFrames(in: subview, frames: &frames)
        }
    }

    private static func isSwiftUIHostingView(_ view: UIView) -> Bool {
        let name = String(describing: type(of: view))
        return name.contains("_UIHostingView") || name.contains("UIHostingView")
    }

    private static func matches(_ candidate: String, query: String, matchMode: String) -> Bool {
        let normalizedCandidate = normalized(candidate)
        let normalizedQuery = normalized(query)
        guard !normalizedCandidate.isEmpty, !normalizedQuery.isEmpty else { return false }

        switch matchMode {
        case "contains":
            return normalizedCandidate.contains(normalizedQuery)
        default:
            return normalizedCandidate == normalizedQuery
        }
    }

    private static func splitIdentifierIntoWords(_ value: String) -> [String] {
        let separated = value
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "[^A-Za-z0-9]+",
                with: " ",
                options: .regularExpression
            )
        return separated
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
    }
}

#endif

#endif
