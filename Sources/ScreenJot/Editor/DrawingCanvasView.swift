import AppKit

/// Shows the captured image and lets the user scribble on it with the mouse.
/// Strokes are stored in image pixel coordinates (bottom-left origin) so the view can
/// be any size and the final render is resolution independent.
final class DrawingCanvasView: NSView {
    struct Stroke {
        var points: [CGPoint]
        var color: NSColor
        var width: CGFloat   // in points at 1:1
    }

    let image: CGImage
    /// Image pixels per screen point at 1:1 (2 on Retina).
    let pointScale: CGFloat
    var strokeColor: NSColor = Preferences.strokeColor
    var strokeWidth: CGFloat = Preferences.strokeWidth
    private(set) var strokes: [Stroke] = []
    private var redoStack: [Stroke] = []
    private var current: Stroke?

    var hasStrokes: Bool { !strokes.isEmpty }

    init(image: CGImage, pointScale: CGFloat) {
        self.image = image
        self.pointScale = pointScale
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// View points -> image pixels.
    private var viewToImage: CGFloat { CGFloat(image.width) / max(bounds.width, 1) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * viewToImage, y: p.y * viewToImage)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        current = Stroke(points: [imagePoint(event)], color: strokeColor, width: strokeWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard current != nil else { return }
        let p = imagePoint(event)
        if let last = current!.points.last, hypot(p.x - last.x, p.y - last.y) < 0.75 * pointScale { return }
        current!.points.append(p)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard var stroke = current else { return }
        current = nil
        if stroke.points.count == 1 {   // a click leaves a dot
            stroke.points.append(CGPoint(x: stroke.points[0].x + 0.01, y: stroke.points[0].y))
        }
        strokes.append(stroke)
        redoStack.removeAll()
        needsDisplay = true
    }

    // MARK: Undo

    func undo() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
        needsDisplay = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        strokes.append(next)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: bounds)
        let scale = 1 / viewToImage
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        for stroke in strokes { draw(stroke, in: ctx) }
        if let current { draw(current, in: ctx) }
        ctx.restoreGState()
    }

    /// Draws a stroke in image pixel space.
    private func draw(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count >= 2 else { return }
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.width * pointScale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(DrawingCanvasView.smoothPath(stroke.points))
        ctx.strokePath()
    }

    private static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: pts[0])
        if pts.count == 2 {
            path.addLine(to: pts[1])
            return path
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    /// Flattens image + strokes to a new bitmap at the image's native pixel size.
    func renderComposite() -> CGImage {
        guard hasStrokes else { return image }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for stroke in strokes { draw(stroke, in: ctx) }
        return ctx.makeImage() ?? image
    }
}
