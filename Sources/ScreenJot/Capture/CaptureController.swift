import AppKit

/// State machine for one capture at a time:
/// idle → selecting (overlays) → capturing/recording → editing/previewing → idle.
final class CaptureController {
    private enum State { case idle, selecting, capturing, editing, recording, previewing }

    private var state = State.idle
    private var mode = CaptureMode.screenshot
    private var target = CaptureTarget.region
    private var overlays: [OverlayWindow] = []
    private var windows: [WindowInfo] = []
    private var previousApp: NSRunningApplication?
    private var editor: EditorController?
    private var preview: GIFPreviewController?
    private var recording: RecordingSession?

    func hotKeyPressed(_ mode: CaptureMode) {
        switch state {
        case .idle:
            begin(mode)
        case .selecting:
            if self.mode == mode {
                cancelSelection()
            } else {
                self.mode = mode
                refreshOverlays()
            }
        case .recording:
            if let recording, recording.canStop { recording.stop() } else { NSSound.beep() }
        case .capturing, .editing, .previewing:
            NSSound.beep()
        }
    }

    // MARK: Selection

    private func begin(_ mode: CaptureMode) {
        guard Permissions.hasScreenRecording else {
            Permissions.presentPermissionAlert()
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        self.mode = mode
        target = Preferences.lastTarget
        windows = WindowList.onScreenWindows()
        state = .selecting

        overlays = NSScreen.screens.map { screen in
            let overlay = OverlayWindow(screen: screen)
            overlay.onEvent = { [weak self] event in self?.handle(event) }
            return overlay
        }
        refreshOverlays()
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        for overlay in overlays { overlay.orderFrontRegardless() }
        (overlays.first { $0.screen_.frame.contains(mouse) } ?? overlays.first)?.makeKeyAndOrderFront(nil)
    }

    private func refreshOverlays() {
        for overlay in overlays { overlay.update(mode: mode, target: target, windows: windows) }
    }

    private func closeOverlays() {
        for overlay in overlays {
            overlay.onEvent = nil
            overlay.orderOut(nil)
        }
        overlays.removeAll()
    }

    private func handle(_ event: OverlayEvent) {
        guard state == .selecting else { return }
        switch event {
        case .cancel:
            cancelSelection()
        case .nextTarget:
            target = target.next
            Preferences.lastTarget = target
            refreshOverlays()
        case .selectedRegion(let rect, let screen):
            didSelect(.region(rect, screen))
        case .selectedWindow(let info):
            didSelect(.window(info))
        case .selectedDisplay(let screen):
            didSelect(.display(screen))
        }
    }

    private func cancelSelection() {
        closeOverlays()
        state = .idle
        restorePreviousApp()
    }

    private func didSelect(_ selection: CaptureSelection) {
        switch mode {
        case .screenshot:
            state = .capturing
            Task { @MainActor in
                do {
                    // Capture before the overlays go away: they are excluded from the filter,
                    // so there is no flash and no risk of catching the dimming.
                    let image = try await ScreenCapturer.capture(selection)
                    closeOverlays()
                    showEditor(image: image, selection: selection)
                } catch {
                    closeOverlays()
                    state = .idle
                    restorePreviousApp()
                    presentError(error)
                }
            }
        case .video:
            closeOverlays()
            startRecording(selection)
        }
    }

    // MARK: Screenshot

    private func showEditor(image: CGImage, selection: CaptureSelection) {
        state = .editing
        editor = EditorController(image: image, sourceFrame: selection.frame, screen: selection.screen) { [weak self] _ in
            guard let self else { return }
            self.editor = nil
            self.state = .idle
            self.restorePreviousApp()
        }
    }

    // MARK: Video

    private func startRecording(_ selection: CaptureSelection) {
        state = .recording
        // Hand focus back so the user can interact with what they are recording.
        restorePreviousApp()
        let session = RecordingSession(selection: selection) { [weak self] outcome in
            guard let self else { return }
            self.recording = nil
            switch outcome {
            case .cancelled:
                self.state = .idle
                self.restorePreviousApp()
            case .failed(let error):
                self.state = .idle
                self.restorePreviousApp()
                self.presentError(error)
            case .finished(let gifURL):
                self.state = .previewing
                self.preview = GIFPreviewController(gifURL: gifURL, sourceFrame: selection.frame, screen: selection.screen) { [weak self] _ in
                    guard let self else { return }
                    self.preview = nil
                    self.state = .idle
                    self.restorePreviousApp()
                }
            }
        }
        recording = session
        session.start()
    }

    // MARK: Helpers

    private func restorePreviousApp() {
        guard let app = previousApp, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        app.activate()
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if !Permissions.hasScreenRecording {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn { Permissions.openScreenRecordingSettings() }
        } else {
            alert.runModal()
        }
    }
}
