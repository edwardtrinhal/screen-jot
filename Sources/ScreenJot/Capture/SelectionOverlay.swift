import AppKit

enum OverlayEvent {
    case selectedRegion(CGRect, NSScreen)
    case selectedWindow(WindowInfo)
    case selectedDisplay(NSScreen)
    case nextTarget
    case cancel
}

/// One per screen. Dims the display, shows the crosshair / window highlight / HUD and
/// reports the user's choice back to the CaptureController.
final class OverlayWindow: KeyableWindow {
    let screen_: NSScreen
    var onEvent: ((OverlayEvent) -> Void)?
    private let selectionView: SelectionView

    init(screen: NSScreen) {
        screen_ = screen
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        contentView = selectionView
        selectionView.onEvent = { [weak self] event in self?.onEvent?(event) }
    }

    func update(mode: CaptureMode, target: CaptureTarget, windows: [WindowInfo]) {
        selectionView.mode = mode
        selectionView.target = target
        selectionView.windows = windows
        selectionView.refreshHover()
        selectionView.needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: onEvent?(.cancel)                       // esc
        case 48: onEvent?(.nextTarget)                   // tab
        case 36, 76: selectionView.confirmCurrent()      // return / enter
        default: break
        }
    }

    override func becomeKey() {
        super.becomeKey()
        selectionView.needsDisplay = true
    }

    override func resignKey() {
        super.resignKey()
        selectionView.needsDisplay = true
    }
}

final class SelectionView: NSView {
    var mode: CaptureMode = .screenshot
    var target: CaptureTarget = .region
    var windows: [WindowInfo] = []
    var onEvent: ((OverlayEvent) -> Void)?

    private let screen: NSScreen
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var hovered: WindowInfo?
    private var mouse: CGPoint?
    private var trackingArea: NSTrackingArea?

    private let dimColor = NSColor.black.withAlphaComponent(0.32)
    private let accent = NSColor.white

    init(frame: CGRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Coordinates

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screen.frame.minX, y: local.y + screen.frame.minY)
    }

    private func toLocal(_ global: CGRect) -> CGRect {
        global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, screen.frame.minX), screen.frame.maxX), y: min(max(p.y, screen.frame.minY), screen.frame.maxY))
    }

    // MARK: Hover / mouse

    func refreshHover() {
        let loc = NSEvent.mouseLocation
        mouse = loc
        hovered = target == .window ? WindowList.window(at: loc, in: windows) : nil
        updateCursor()
    }

    private func updateCursor() {
        switch target {
        case .region: NSCursor.crosshair.set()
        case .window, .fullScreen: NSCursor.pointingHand.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if let window, !window.isKeyWindow { window.makeKey() }
        mouse = globalPoint(event)
        if target == .window { hovered = WindowList.window(at: mouse!, in: windows) }
        updateCursor()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { updateCursor() }

    override func mouseDown(with event: NSEvent) {
        let p = globalPoint(event)
        switch target {
        case .region:
            dragStart = p
            selection = CGRect(origin: p, size: .zero)
        case .window:
            if let w = WindowList.window(at: p, in: windows) { onEvent?(.selectedWindow(w)) }
        case .fullScreen:
            onEvent?(.selectedDisplay(screen))
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard target == .region, let start = dragStart else { return }
        let p = clampToScreen(globalPoint(event))
        mouse = p
        var rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        if event.modifierFlags.contains(.shift) {   // square
            let side = max(rect.width, rect.height)
            rect.size = CGSize(width: side, height: side)
            if p.x < start.x { rect.origin.x = start.x - side }
            if p.y < start.y { rect.origin.y = start.y - side }
        }
        selection = rect.intersection(screen.frame)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard target == .region, dragStart != nil else { return }
        dragStart = nil
        let rect = (selection ?? .zero).integral
        selection = nil
        needsDisplay = true
        if rect.width >= 4 && rect.height >= 4 {
            onEvent?(.selectedRegion(rect, screen))
        }
    }

    /// Return key: confirm the hovered window or this display.
    func confirmCurrent() {
        switch target {
        case .window: if let hovered { onEvent?(.selectedWindow(hovered)) }
        case .fullScreen: onEvent?(.selectedDisplay(screen))
        case .region: break
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let isKey = window?.isKeyWindow ?? false

        // Highlighted area (kept undimmed).
        var highlight: CGRect?
        switch target {
        case .region: if let s = selection, !s.isEmpty { highlight = toLocal(s) }
        case .window: if let h = hovered { highlight = toLocal(h.frame.intersection(screen.frame)) }
        case .fullScreen: if isKey { highlight = bounds }
        }

        ctx.setFillColor(dimColor.cgColor)
        ctx.fill(bounds)
        if let highlight, !highlight.isNull {
            ctx.clear(highlight)
        }

        if let highlight, !highlight.isNull {
            // Border: dark outer line + white inner line reads on any background.
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(highlight.insetBy(dx: -1.5, dy: -1.5))
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(highlight.insetBy(dx: -0.5, dy: -0.5))

            var label = "\(Int(highlight.width)) × \(Int(highlight.height))"
            if target == .window, let h = hovered {
                label = h.title.isEmpty ? "\(h.ownerName)  ·  \(label)" : "\(h.ownerName) — \(h.title)  ·  \(label)"
            }
            if target == .fullScreen { label = "\(screen.localizedName)  ·  \(label)" }
            drawPill(label, at: CGPoint(x: highlight.midX, y: highlight.minY - 22), in: ctx, font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        }

        // Crosshair in region mode while not dragging.
        if target == .region, dragStart == nil, let m = mouse, screen.frame.contains(m) {
            let local = CGPoint(x: m.x - screen.frame.minX, y: m.y - screen.frame.minY)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: local.x + 0.5, y: 0)); ctx.addLine(to: CGPoint(x: local.x + 0.5, y: bounds.height))
            ctx.move(to: CGPoint(x: 0, y: local.y + 0.5)); ctx.addLine(to: CGPoint(x: bounds.width, y: local.y + 0.5))
            ctx.strokePath()
        }

        if isKey { drawHUD(in: ctx) }
    }

    private func drawHUD(in ctx: CGContext) {
        let targets = CaptureTarget.allCases.map { $0 == target ? "[\($0.title)]" : $0.title }.joined(separator: "   ")
        let text = "\(mode.title)     \(targets)     Tab switch  ·  esc cancel"
        let center = CGPoint(x: bounds.midX, y: bounds.maxY - 48)
        drawPill(text, at: center, in: ctx, font: .systemFont(ofSize: 13, weight: .medium), padding: CGSize(width: 18, height: 10))
    }

    private func drawPill(_ text: String, at center: CGPoint, in ctx: CGContext, font: NSFont, padding: CGSize = CGSize(width: 10, height: 5)) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var rect = CGRect(x: center.x - size.width / 2 - padding.width, y: center.y - size.height / 2 - padding.height,
                          width: size.width + padding.width * 2, height: size.height + padding.height * 2)
        rect.origin.x = min(max(rect.minX, 8), bounds.maxX - rect.width - 8)
        rect.origin.y = min(max(rect.minY, 8), bounds.maxY - rect.height - 8)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        str.draw(at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height))
    }
}
