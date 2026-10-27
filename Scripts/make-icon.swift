// Renders the app icon programmatically so the repo carries no binary assets.
// Usage: swift Scripts/make-icon.swift <output.iconset>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    let s = size / 1024
    let inset = 100 * s   // macOS icon grid margin
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let colors = [NSColor(srgbRed: 0.16, green: 0.17, blue: 0.24, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.07, green: 0.08, blue: 0.12, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()

    // Viewfinder corners.
    let vf = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.2)
    let arm = vf.width * 0.22
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.setLineWidth(max(1, 44 * s))
    ctx.setLineCap(.round)
    for (cx, cy, dx, dy) in [(vf.minX, vf.minY, 1.0, 1.0), (vf.maxX, vf.minY, -1.0, 1.0), (vf.minX, vf.maxY, 1.0, -1.0), (vf.maxX, vf.maxY, -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: cx + dx * arm, y: cy)); ctx.addLine(to: CGPoint(x: cx, y: cy)); ctx.addLine(to: CGPoint(x: cx, y: cy + dy * arm))
    }
    ctx.strokePath()

    // Red scribble.
    ctx.setStrokeColor(NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1).cgColor)
    ctx.setLineWidth(max(1, 58 * s))
    ctx.setLineJoin(.round)
    let p = CGMutablePath()
    let w = vf.width, h = vf.height
    p.move(to: CGPoint(x: vf.minX + w * 0.18, y: vf.minY + h * 0.42))
    p.addCurve(to: CGPoint(x: vf.minX + w * 0.50, y: vf.minY + h * 0.62),
               control1: CGPoint(x: vf.minX + w * 0.22, y: vf.minY + h * 0.95),
               control2: CGPoint(x: vf.minX + w * 0.40, y: vf.minY + h * 0.95))
    p.addCurve(to: CGPoint(x: vf.minX + w * 0.84, y: vf.minY + h * 0.52),
               control1: CGPoint(x: vf.minX + w * 0.60, y: vf.minY + h * 0.30),
               control2: CGPoint(x: vf.minX + w * 0.74, y: vf.minY + h * 0.20))
    ctx.addPath(p)
    ctx.strokePath()
    image.unlockFocus()
    return image
}

func write(_ image: NSImage, _ name: String) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    write(render(size: CGFloat(base)), "icon_\(base)x\(base).png")
    write(render(size: CGFloat(base * 2)), "icon_\(base)x\(base)@2x.png")
}
print("iconset written to \(outDir)")
