// macOS screen capture using CGWindowListCreateImage and NSBitmapImageRep

import Foundation

#if DEBUG
#if os(macOS)

import AppKit

@MainActor
final class MacOSScreenshotCapture {

    static let shared = MacOSScreenshotCapture()

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

        let windowNumber = CGWindowID(ref.nativeWindow.windowNumber)
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowNumber,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = encodeImage(bitmapRep, format: format) else {
            return nil
        }

        return CaptureResult(
            imageData: data,
            width: cgImage.width,
            height: cgImage.height,
            scale: ref.nativeWindow.backingScaleFactor,
            format: format.rawValue
        )
    }

    func captureElement(id: String, format: ImageFormat = .png, windowId: String? = nil) -> CaptureResult? {
        guard let view = ElementInventory.shared.findElement(byId: id, windowId: windowId) else {
            return nil
        }

        view.layoutSubtreeIfNeeded()

        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }

        view.cacheDisplay(in: view.bounds, to: bitmapRep)

        guard let data = encodeImage(bitmapRep, format: format) else {
            return nil
        }

        return CaptureResult(
            imageData: data,
            width: bitmapRep.pixelsWide,
            height: bitmapRep.pixelsHigh,
            scale: view.window?.backingScaleFactor ?? 1.0,
            format: format.rawValue
        )
    }

    private func encodeImage(_ image: NSBitmapImageRep, format: ImageFormat) -> Data? {
        switch format {
        case .png:
            return image.pngData
        case .jpeg:
            return image.jpegData
        }
    }
}

private extension NSBitmapImageRep {
    var pngData: Data? {
        representation(using: .png, properties: [:])
    }

    var jpegData: Data? {
        representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

#endif // os(macOS)
#endif // DEBUG
