import AppKit

enum CaptureMode {
    case screenshot
    case video

    var title: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .video: return "GIF Recording"
        }
    }
}

enum CaptureTarget: String, CaseIterable {
    case region
    case window
    case fullScreen

    var next: CaptureTarget {
        let all = CaptureTarget.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var title: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullScreen: return "Full Screen"
        }
    }
}

/// An on-screen window from another app, with its frame in AppKit global coordinates.
struct WindowInfo: Equatable {
    let id: CGWindowID
    let frame: CGRect
    let ownerName: String
    let title: String
    let pid: pid_t
}

/// What the user picked in the overlay. Frames are AppKit global coordinates.
enum CaptureSelection {
    case region(CGRect, NSScreen)
    case window(WindowInfo)
    case display(NSScreen)

    var frame: CGRect {
        switch self {
        case .region(let rect, _): return rect
        case .window(let info): return info.frame
        case .display(let screen): return screen.frame
        }
    }

    var screen: NSScreen {
        switch self {
        case .region(_, let screen): return screen
        case .display(let screen): return screen
        case .window(let info): return NSScreen.screen(containing: info.frame) ?? NSScreen.main ?? NSScreen.screens[0]
        }
    }
}
