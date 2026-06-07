// Debug overlay that draws a persistent crosshair at every dispatched tap point.
// Subscribes to appRevealTapPointNotificationName posted by InteractionEngine.

import Foundation

#if os(iOS)
import UIKit

#if DEBUG

@MainActor
final class TapImprintOverlay {

    static let shared = TapImprintOverlay()

    private var overlayWindow: UIWindow?
    private var canvas: TapImprintCanvas?

    private(set) var isEnabled = false
    var color: UIColor = .systemRed
    var crosshairSize: CGFloat = 20
    var showLabel: Bool = true
    var labelFont: UIFont = .monospacedSystemFont(ofSize: 10, weight: .regular)
    var persist: Bool = true

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTap(_:)),
            name: appRevealTapPointNotificationName,
            object: nil
        )
    }

    func enable(
        color: UIColor? = nil,
        crosshairSize: CGFloat? = nil,
        showLabel: Bool? = nil,
        labelFont: UIFont? = nil,
        persist: Bool? = nil
    ) {
        if let c = color { self.color = c }
        if let s = crosshairSize { self.crosshairSize = s }
        if let l = showLabel { self.showLabel = l }
        if let f = labelFont { self.labelFont = f }
        if let p = persist { self.persist = p }
        isEnabled = true
        ensureWindow()
    }

    func reset() {
        canvas?.clearImprints()
    }

    func disable() {
        isEnabled = false
        canvas?.clearImprints()
        overlayWindow?.isHidden = true
    }

    @objc private func onTap(_ notification: Notification) {
        guard isEnabled,
              let value = notification.userInfo?[appRevealTapPointUserInfoKey] as? NSValue else { return }
        let point = value.cgPointValue
        if !persist { canvas?.clearImprints() }
        canvas?.addImprint(at: point, color: color, size: crosshairSize, showLabel: showLabel, font: labelFont)
    }

    private func ensureWindow() {
        if let existing = overlayWindow {
            existing.isHidden = false
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let win = UIWindow(windowScene: scene)
        win.windowLevel = UIWindow.Level.alert + 1000
        win.isUserInteractionEnabled = false
        win.backgroundColor = .clear

        let view = TapImprintCanvas()
        view.frame = win.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        win.addSubview(view)
        win.isHidden = false

        overlayWindow = win
        canvas = view
    }
}

// MARK: - Canvas view

private final class TapImprintCanvas: UIView {

    private struct Imprint {
        let point: CGPoint
        let color: UIColor
        let size: CGFloat
        let showLabel: Bool
        let font: UIFont
    }

    private var imprints: [Imprint] = []

    func addImprint(at point: CGPoint, color: UIColor, size: CGFloat, showLabel: Bool, font: UIFont) {
        imprints.append(Imprint(point: point, color: color, size: size, showLabel: showLabel, font: font))
        setNeedsDisplay()
    }

    func clearImprints() {
        imprints.removeAll()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for imp in imprints {
            drawImprint(imp, in: ctx)
        }
    }

    private func drawImprint(_ imp: Imprint, in ctx: CGContext) {
        let x = imp.point.x
        let y = imp.point.y
        let half = imp.size / 2

        ctx.setStrokeColor(imp.color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [])

        // Horizontal arm
        ctx.move(to: CGPoint(x: x - half, y: y))
        ctx.addLine(to: CGPoint(x: x + half, y: y))
        // Vertical arm
        ctx.move(to: CGPoint(x: x, y: y - half))
        ctx.addLine(to: CGPoint(x: x, y: y + half))
        ctx.strokePath()

        // Circle at center
        let dotRadius: CGFloat = 3
        ctx.setFillColor(imp.color.cgColor)
        ctx.fillEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

        guard imp.showLabel else { return }

        let label = "(\(Int(x.rounded())),\(Int(y.rounded())))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: imp.font,
            .foregroundColor: imp.color
        ]
        let size = label.size(withAttributes: attrs)
        let labelX = min(x + dotRadius + 3, bounds.width - size.width - 2)
        let labelY = max(y - size.height / 2, 2)
        label.draw(at: CGPoint(x: labelX, y: labelY), withAttributes: attrs)
    }
}

// MARK: - UIColor hex init

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

#endif
#endif
