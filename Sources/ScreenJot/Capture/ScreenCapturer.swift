import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case noPermission

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The display could not be found."
        case .windowNotFound: return "The window is no longer on screen."
        case .noPermission: return "Screen Recording permission is required."
        }
    }
}

/// Still-image capture via ScreenCaptureKit. Our own overlay windows are excluded from
/// the content filter so the dimming never shows up in the result.
enum ScreenCapturer {
    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Builds a display filter that leaves out every window owned by this process.
    static func displayFilter(for screen: NSScreen, content: SCShareableContent) throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let own = content.windows.filter { $0.owningApplication?.processID == ownPID }
        return SCContentFilter(display: display, excludingWindows: own)
    }

    static func capture(_ selection: CaptureSelection) async throws -> CGImage {
        let content = try await shareableContent()
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true

        let filter: SCContentFilter
        let scale: CGFloat
        switch selection {
        case .region(let rect, let screen):
            filter = try displayFilter(for: screen, content: content)
            scale = screen.backingScaleFactor
            config.sourceRect = rect.displayLocalTopLeft(in: screen)
            config.width = Int(rect.width * scale)
            config.height = Int(rect.height * scale)
        case .display(let screen):
            filter = try displayFilter(for: screen, content: content)
            scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.id }) else { throw CaptureError.windowNotFound }
            filter = SCContentFilter(desktopIndependentWindow: window)
            scale = selection.screen.backingScaleFactor
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
