// Screen capture using UIGraphicsImageRenderer

import Foundation
import UIKit

#if DEBUG

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

    func captureScreen(format: ImageFormat = .png) -> CaptureResult? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
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

    func captureElement(id: String, format: ImageFormat = .png) -> CaptureResult? {
        guard let view = ElementInventory.shared.findElement(byId: id) else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { context in
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

enum ImageFormat: String, Codable {
    case png
    case jpeg
}

#endif
