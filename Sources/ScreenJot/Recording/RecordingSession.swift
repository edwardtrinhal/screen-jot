import AppKit
import ScreenCaptureKit

enum RecordingOutcome {
    case cancelled
    case finished(gifURL: URL)
    case failed(Error)
}

/// Drives one recording: red frame around the target, HUD with timer and stop button,
/// the stream itself, the 30 s cap, and the GIF conversion afterwards.
final class RecordingSession {
    private let selection: CaptureSelection
    private let fps = Preferences.gifFramesPerSecond
    private let maxSeconds = Preferences.gifMaxSeconds
    private var recorder: ScreenRecorder?
    private var border: BorderWindow?
    private var hud: RecordingHUD?
    private var timer: Timer?
    private var startedAt: Date?
    private var state = State.starting
    private var completion: ((RecordingOutcome) -> Void)?

    private enum State { case starting, recording, stopping, converting, done }

    init(selection: CaptureSelection, completion: @escaping (RecordingOutcome) -> Void) {
        self.selection = selection
        self.completion = completion
    }

    func start() {
        let frame = selection.frame
        let screen = selection.screen
        border = BorderWindow(frame: frame)
        hud = RecordingHUD(onStop: { [weak self] in self?.stop() }, onCancel: { [weak self] in self?.cancel() })
        hud?.attach(below: frame, on: screen)
        border?.orderFrontRegardless()
        hud?.show()

        Task { @MainActor in
            do {
                let content = try await ScreenCapturer.shareableContent()
                let filter: SCContentFilter
                var sourceRect: CGRect?
                switch selection {
                case .region(let rect, let screen):
                    filter = try ScreenCapturer.displayFilter(for: screen, content: content)
                    sourceRect = rect.displayLocalTopLeft(in: screen)
                case .display(let screen):
                    filter = try ScreenCapturer.displayFilter(for: screen, content: content)
                case .window(let info):
                    guard let window = content.windows.first(where: { $0.windowID == info.id }) else { throw CaptureError.windowNotFound }
                    filter = SCContentFilter(desktopIndependentWindow: window)
                }
                let movieURL = TempFiles.url(named: "recording-\(UUID().uuidString).mov")
                // 1x output: GIFs at Retina resolution are huge and rarely wanted.
                let recorder = try ScreenRecorder(filter: filter, sourceRect: sourceRect, outputSize: frame.size, fps: fps, outputURL: movieURL)
                recorder.onStreamError = { [weak self] error in self?.fail(error) }
                self.recorder = recorder
                try await recorder.start()
                guard state == .starting else { return }   // cancelled while starting
                state = .recording
                startedAt = Date()
                hud?.setRecording(elapsed: 0, max: maxSeconds)
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
            } catch {
                fail(error)
            }
        }
    }

    private func tick() {
        guard state == .recording, let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        hud?.setRecording(elapsed: elapsed, max: maxSeconds)
        if elapsed >= maxSeconds { stop() }
    }

    func stop() {
        guard state == .recording, let recorder, let startedAt else {
            if state == .starting { cancel() }
            return
        }
        state = .stopping
        timer?.invalidate()
        let elapsed = Date().timeIntervalSince(startedAt)
        hud?.setConverting(progress: 0)
        border?.orderOut(nil)

        Task { @MainActor in
            do {
                let movieURL = try await recorder.stop()
                state = .converting
                let gifURL = TempFiles.url(named: "Recording \(TempFiles.timestamp()).gif")
                let fps = self.fps
                let duration = max(elapsed, recorder.writtenDuration)
                try await Task.detached(priority: .userInitiated) {
                    try await MovieToGIF.convert(movieURL: movieURL, to: gifURL, fps: fps, totalDuration: duration) { p in
                        DispatchQueue.main.async { self.hud?.setConverting(progress: p) }
                    }
                }.value
                try? FileManager.default.removeItem(at: movieURL)
                finish(.finished(gifURL: gifURL))
            } catch {
                fail(error)
            }
        }
    }

    func cancel() {
        guard state == .starting || state == .recording else { return }
        state = .done
        timer?.invalidate()
        let recorder = self.recorder
        Task { @MainActor in
            await recorder?.cancel()
        }
        finish(.cancelled)
    }

    private func fail(_ error: Error) {
        guard state != .done else { return }
        timer?.invalidate()
        finish(.failed(error))
    }

    private func finish(_ outcome: RecordingOutcome) {
        state = .done
        border?.orderOut(nil)
        hud?.orderOut(nil)
        border = nil
        hud = nil
        completion?(outcome)
        completion = nil
    }
}

/// Click-through red frame marking the recorded area.
final class BorderWindow: NSWindow {
    init(frame: CGRect) {
        let outset = frame.insetBy(dx: -3, dy: -3)
        super.init(contentRect: outset, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BorderView(frame: CGRect(origin: .zero, size: outset.size))
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
            path.lineWidth = 3
            NSColor.systemRed.setStroke()
            path.stroke()
        }
    }
}

/// Timer + Stop button. Key so ⏎ / esc work; the global hotkeys also stop it.
final class RecordingHUD: KeyableWindow {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private var blink: Timer?

    init(onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onStop = onStop
        self.onCancel = onCancel
        super.init(contentRect: CGRect(x: 0, y: 0, width: 300, height: 44), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        contentView = effect

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5

        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        hintLabel.attributedStringValue = HUDPanel.styled("⏎ Stop  ·  esc Cancel")
        hintLabel.font = .systemFont(ofSize: 11)

        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.target = self
        stopButton.action = #selector(stopPressed)
        stopButton.keyEquivalent = "\r"

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.isHidden = true

        let stack = NSStackView(views: [dot, label, hintLabel, stopButton, progress])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            progress.widthAnchor.constraint(equalToConstant: 120),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        label.stringValue = "Starting…"
        resize()
    }

    private func resize() {
        contentView?.layoutSubtreeIfNeeded()
        let size = contentView?.fittingSize ?? CGSize(width: 300, height: 44)
        let origin = frame.origin
        setFrame(CGRect(origin: origin, size: size), display: true)
    }

    func attach(below frame: CGRect, on screen: NSScreen) {
        let size = self.frame.size
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.minY - 12 - size.height)
        let visible = screen.visibleFrame
        if origin.y < visible.minY { origin.y = frame.maxY + 12 }
        if origin.y + size.height > visible.maxY { origin.y = frame.minY + 12 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        setFrameOrigin(origin)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        blink = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dot.animator().alphaValue = self.dot.alphaValue < 0.5 ? 1 : 0.25
        }
    }

    func setRecording(elapsed: TimeInterval, max: TimeInterval) {
        label.stringValue = "\(format(elapsed)) / \(format(max))"
    }

    func setConverting(progress p: Double) {
        if !progress.isHidden && p > 0 {
            progress.doubleValue = p
            return
        }
        blink?.invalidate()
        dot.alphaValue = 0.25
        label.stringValue = "Converting to GIF…"
        hintLabel.isHidden = true
        stopButton.isHidden = true
        progress.isHidden = false
        progress.doubleValue = p
        let center = frame.midX
        resize()
        setFrameOrigin(CGPoint(x: center - frame.width / 2, y: frame.minY))
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    @objc private func stopPressed() { onStop() }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: onCancel()
        case 36, 76: onStop()
        default: super.keyDown(with: event)
        }
    }

    override func orderOut(_ sender: Any?) {
        blink?.invalidate()
        super.orderOut(sender)
    }
}
