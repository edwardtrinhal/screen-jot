import AppKit

enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let overrideSystemShortcuts = "overrideSystemShortcuts"
        static let lastSaveDirectory = "lastSaveDirectory"
        static let lastTarget = "lastCaptureTarget"
    }

    static var overrideSystemShortcuts: Bool {
        get { defaults.object(forKey: Key.overrideSystemShortcuts) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.overrideSystemShortcuts) }
    }

    static var lastSaveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.lastSaveDirectory), FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: Key.lastSaveDirectory) }
    }

    static var lastTarget: CaptureTarget {
        get { CaptureTarget(rawValue: defaults.string(forKey: Key.lastTarget) ?? "") ?? .region }
        set { defaults.set(newValue.rawValue, forKey: Key.lastTarget) }
    }

    // Recording settings (fixed for now; surfaced here so they are easy to expose later).
    static let gifFramesPerSecond = 15
    static let gifMaxSeconds: TimeInterval = 30

    // Drawing defaults.
    static let strokeColor = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)   // system red
    static let strokeWidth: CGFloat = 4
}
