import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? 0
    }

    /// The screen whose frame contains the point, if any.
    static func screen(at point: CGPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// The screen that overlaps the rect the most.
    static func screen(containing rect: CGRect) -> NSScreen? {
        screens.max { a, b in
            a.frame.intersection(rect).area < b.frame.intersection(rect).area
        }
    }

    /// Primary screen height, needed to flip between Quartz (top-left) and AppKit (bottom-left) coordinates.
    static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }
}

extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }

    /// Quartz global (top-left origin) -> AppKit global (bottom-left origin).
    var fromQuartz: CGRect {
        CGRect(x: minX, y: NSScreen.primaryHeight - maxY, width: width, height: height)
    }

    /// AppKit global -> Quartz global.
    var toQuartz: CGRect {
        CGRect(x: minX, y: NSScreen.primaryHeight - maxY, width: width, height: height)
    }

    /// AppKit global rect -> rect local to `screen` with a top-left origin, as
    /// ScreenCaptureKit's sourceRect expects.
    func displayLocalTopLeft(in screen: NSScreen) -> CGRect {
        CGRect(x: minX - screen.frame.minX, y: screen.frame.maxY - maxY, width: width, height: height)
    }

    /// Moves (and if necessary shrinks) the rect so it fits inside `bounds`, preserving aspect ratio when shrinking.
    func fitted(into bounds: CGRect) -> CGRect {
        var r = self
        if r.width > bounds.width || r.height > bounds.height {
            let scale = min(bounds.width / r.width, bounds.height / r.height)
            r.size = CGSize(width: floor(r.width * scale), height: floor(r.height * scale))
        }
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }
}
