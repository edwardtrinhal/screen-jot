import AppKit

enum WindowList {
    /// On-screen, normal-layer windows of other apps, front to back, in AppKit coordinates.
    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ignoredOwners: Set<String> = ["Dock", "Window Server", "Control Center", "Notification Center", "Spotlight"]
        var result: [WindowInfo] = []
        for entry in list {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 24, bounds.height >= 24
            else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwners.contains(owner) { continue }
            let title = entry[kCGWindowName as String] as? String ?? ""
            result.append(WindowInfo(id: id, frame: bounds.fromQuartz, ownerName: owner, title: title, pid: pid))
        }
        return result
    }

    /// Topmost listed window under the point (AppKit coordinates).
    static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
