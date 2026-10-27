import Foundation

/// Toggles the built-in macOS screenshot shortcuts that collide with ours.
///
/// macOS consumes ⌘⇧4 / ⌘⇧5 before any app sees them, so the only way to "override"
/// them is to disable the system bindings in com.apple.symbolichotkeys and tell the
/// system to reload its hotkey table.
enum SystemShortcuts {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString

    /// Symbolic hotkey IDs: 30 = "Save picture of selected area as a file" (⌘⇧4),
    /// 184 = "Screenshot and recording options" (⌘⇧5).
    /// Parameters are [ASCII code, virtual key code, modifier flags] where
    /// 0x120000 = Shift + Command.
    private static let entries: [(id: String, parameters: [Int])] = [
        ("30", [52, 21, 0x120000]),
        ("184", [53, 23, 0x120000]),
    ]

    static func setNativeShortcutsEnabled(_ enabled: Bool) {
        var table = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
        for entry in entries {
            var record = table[entry.id] as? [String: Any] ?? [:]
            record["enabled"] = enabled
            if record["value"] == nil {
                record["value"] = ["parameters": entry.parameters, "type": "standard"]
            }
            table[entry.id] = record
        }
        CFPreferencesSetAppValue(key, table as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        reloadSystemHotKeys()
    }

    static var nativeShortcutsEnabled: Bool {
        guard let table = CFPreferencesCopyAppValue(key, domain) as? [String: Any] else { return true }
        return entries.allSatisfy { entry in
            guard let record = table[entry.id] as? [String: Any], let enabled = record["enabled"] as? Bool else { return true }
            return enabled
        }
    }

    /// Asks the system to re-read the symbolic hotkey preferences without a logout.
    private static func reloadSystemHotKeys() {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            NSLog("ScreenJot: activateSettings not found; shortcut changes apply after next login")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-u"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("ScreenJot: activateSettings failed: \(error)")
        }
    }
}
