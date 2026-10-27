import AppKit

enum Permissions {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system permission prompt (only shown once per app identity).
    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    static func presentPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ScreenJot needs Screen Recording access"
        alert.informativeText = """
        Enable ScreenJot under System Settings › Privacy & Security › Screen & System Audio Recording, \
        then relaunch ScreenJot.

        If ScreenJot is already switched on there, the saved permission belongs to an older build. \
        Click “Reset Permission”, switch it on again when asked, and relaunch.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch ScreenJot")
        alert.addButton(withTitle: "Reset Permission")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn: openScreenRecordingSettings()
        case .alertSecondButtonReturn: relaunch()
        case .alertThirdButtonReturn:
            resetScreenRecordingRecord()
            relaunch()
        default: break
        }
    }

    /// Clears this app's Screen Recording record so macOS prompts fresh on next launch.
    /// Needed when the record was created by a build with a different code signature.
    static func resetScreenRecordingRecord() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        // The record is gone, so the app is no longer listed in Settings; let the next launch
        // trigger the native prompt again to re-register it.
        Preferences.hasRequestedScreenRecording = false
    }

    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
