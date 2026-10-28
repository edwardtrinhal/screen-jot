import AppKit

/// Menu-bar glyph: the app icon's viewfinder corners and scribble, drawn as a template image
/// so it follows the menu bar's light/dark appearance. Same geometry as Scripts/make-icon.swift,
/// minus the background tile.
enum StatusIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let vf = CGRect(x: 1.5, y: 1.5, width: 15, height: 15)
            let arm = vf.width * 0.3

            // Viewfinder corners.
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for (cx, cy, dx, dy) in [(vf.minX, vf.minY, 1.0, 1.0), (vf.maxX, vf.minY, -1.0, 1.0),
                                     (vf.minX, vf.maxY, 1.0, -1.0), (vf.maxX, vf.maxY, -1.0, -1.0)] {
                ctx.move(to: CGPoint(x: cx + dx * arm, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy + dy * arm))
            }
            ctx.strokePath()

            // Scribble.
            let w = vf.width, h = vf.height
            let p = CGMutablePath()
            p.move(to: CGPoint(x: vf.minX + w * 0.18, y: vf.minY + h * 0.42))
            p.addCurve(to: CGPoint(x: vf.minX + w * 0.50, y: vf.minY + h * 0.62),
                       control1: CGPoint(x: vf.minX + w * 0.22, y: vf.minY + h * 0.95),
                       control2: CGPoint(x: vf.minX + w * 0.40, y: vf.minY + h * 0.95))
            p.addCurve(to: CGPoint(x: vf.minX + w * 0.84, y: vf.minY + h * 0.52),
                       control1: CGPoint(x: vf.minX + w * 0.60, y: vf.minY + h * 0.30),
                       control2: CGPoint(x: vf.minX + w * 0.74, y: vf.minY + h * 0.20))
            ctx.setLineWidth(2)
            ctx.addPath(p)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ScreenJot"
        return image
    }
}
