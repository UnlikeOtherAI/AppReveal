// Screen capture using UIGraphicsImageRenderer (iOS) / NSWindow snapshot (macOS)

import Foundation

#if DEBUG

/// Image format for screenshots -- shared across platforms.
enum ImageFormat: String, Codable {
    case png
    case jpeg
}

#if os(iOS)

import UIKit

@MainActor
final class ScreenshotCapture {

    static let shared = ScreenshotCapture()

    private init() {}

    struct CaptureResult {
        let imageData: Data
        let width: Int
        let height: Int
        let scale: CGFloat
        let format: String
    }

    func captureScreen(format: ImageFormat = .png, windowId: String? = nil) -> CaptureResult? {
        guard let ref = platformWindowProvider.resolve(windowId: windowId) else {
            return nil
        }
        let window = ref.nativeWindow

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        guard let data = encodeImage(image, format: format) else { return nil }

        return CaptureResult(
            imageData: data,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            scale: image.scale,
            format: format.rawValue
        )
    }

    func captureElement(id: String, format: ImageFormat = .png, windowId: String? = nil) -> CaptureResult? {
        guard let view = ElementInventory.shared.findElement(byId: id, windowId: windowId) else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }

        guard let data = encodeImage(image, format: format) else { return nil }

        return CaptureResult(
            imageData: data,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            scale: image.scale,
            format: format.rawValue
        )
    }

    private func encodeImage(_ image: UIImage, format: ImageFormat) -> Data? {
        switch format {
        case .png: return image.pngData()
        case .jpeg: return image.jpegData(compressionQuality: 0.85)
        }
    }
}

#endif // os(iOS)

#endif // DEBUG
