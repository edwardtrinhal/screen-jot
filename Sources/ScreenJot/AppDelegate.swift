import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()
    private let capture = CaptureController()
    private var overrideItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var availableUpdate: (version: String, download: URL)?

    private enum HotKeyID: UInt32 { case screenshot = 1, video = 2 }

    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        TempFiles.cleanUpOldFiles()
        setupStatusItem()
        installSignalHandler()
        scheduleBackgroundUpdateChecks()

        hotKeys.onHotKey = { [weak self] id in
            guard let self, let key = HotKeyID(rawValue: id) else { return }
            switch key {
            case .screenshot: self.capture.hotKeyPressed(.screenshot)
            case .video: self.capture.hotKeyPressed(.video)
            }
        }
        hotKeys.register(id: HotKeyID.screenshot.rawValue, keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
        hotKeys.register(id: HotKeyID.video.rawValue, keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey))

        if Preferences.overrideSystemShortcuts {
            SystemShortcuts.setNativeShortcutsEnabled(false)
        }

        if !Permissions.hasScreenRecording {
            // One dialog per launch. The native prompt is unavoidable the first time: it is what
            // registers ScreenJot in the Screen Recording list. After that macOS never shows it
            // again, so later launches get our own alert instead.
            if Preferences.hasRequestedScreenRecording {
                Permissions.presentPermissionAlert()
            } else {
                Preferences.hasRequestedScreenRecording = true
                Permissions.requestScreenRecording()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Preferences.overrideSystemShortcuts {
            SystemShortcuts.setNativeShortcutsEnabled(true)
        }
    }

    /// `kill <pid>` / logout send SIGTERM, which would skip applicationWillTerminate and leave the
    /// native shortcuts disabled. Turn it into a normal quit instead.
    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.stopModal()
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusIcon.make()
            button.toolTip = "ScreenJot"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let shot = NSMenuItem(title: "Take Screenshot", action: #selector(menuScreenshot), keyEquivalent: "4")
        shot.keyEquivalentModifierMask = [.command, .shift]
        shot.target = self
        menu.addItem(shot)

        let rec = NSMenuItem(title: "Record GIF", action: #selector(menuRecord), keyEquivalent: "5")
        rec.keyEquivalentModifierMask = [.command, .shift]
        rec.target = self
        menu.addItem(rec)

        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Tab cycles Region / Window / Full Screen", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        overrideItem = NSMenuItem(title: "Override Native ⌘⇧4 / ⌘⇧5", action: #selector(toggleOverride), keyEquivalent: "")
        overrideItem.target = self
        menu.addItem(overrideItem)

        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        permissionItem = NSMenuItem(title: "Screen Recording: checking…", action: #selector(openPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "ScreenJot \(UpdateChecker.currentVersion)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let quit = NSMenuItem(title: "Quit ScreenJot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func menuScreenshot() {
        // Let the menu close before the overlay appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.capture.hotKeyPressed(.screenshot) }
    }

    @objc private func menuRecord() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.capture.hotKeyPressed(.video) }
    }

    @objc private func toggleOverride() {
        let enable = !Preferences.overrideSystemShortcuts
        Preferences.overrideSystemShortcuts = enable
        SystemShortcuts.setNativeShortcutsEnabled(!enable)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove ScreenJot.app to /Applications and try again."
            alert.runModal()
        }
    }

    @objc private func openPermission() {
        Permissions.openScreenRecordingSettings()
    }

    // MARK: - Updates

    @objc private func checkForUpdates() {
        if let update = availableUpdate {
            // Background check already found it: go straight to the download.
            NSWorkspace.shared.open(update.download)
            return
        }
        updateItem.isEnabled = false
        updateItem.title = "Checking for Updates…"
        Task { @MainActor in
            await UpdateChecker.checkAndPresent()
            updateItem.isEnabled = true
            updateItem.title = "Check for Updates…"
        }
    }

    /// Quiet check shortly after launch and once a day after that. A newer version is only
    /// surfaced as a menu item, never as a dialog; no network traffic besides this.
    private func scheduleBackgroundUpdateChecks() {
        func run() {
            Task { @MainActor in
                if case .available(let version, let download) = await UpdateChecker.check() {
                    availableUpdate = (version, download)
                    updateItem.title = "Download ScreenJot \(version)…"
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { run() }
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in run() }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        overrideItem.state = Preferences.overrideSystemShortcuts ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissionItem.title = Permissions.hasScreenRecording ? "Screen Recording: Granted" : "Screen Recording: Not Granted…"
    }
}
