import AppKit
import UniformTypeIdentifiers

enum EditorOutcome {
    case cancelled
    case copied
    case saved(URL)
}

/// Floating, borderless editor placed exactly where the capture came from, with a hint
/// pill underneath. Keyboard: draw with the mouse, ⏎ copy, ⇧⏎ save, ⌘Z/⇧⌘Z undo/redo, esc cancel.
/// Clicking anywhere else (losing key status) copies and dismisses, same as ⏎.
final class EditorController: NSObject {
    private let window: EditorWindow
    private let canvas: DrawingCanvasView
    private let hint: HUDPanel
    private let screen: NSScreen
    private let pointScale: CGFloat
    private var completion: ((EditorOutcome) -> Void)?
    private var busy = false

    init(image: CGImage, sourceFrame: CGRect, screen: NSScreen, completion: @escaping (EditorOutcome) -> Void) {
        self.screen = screen
        self.completion = completion
        pointScale = CGFloat(image.width) / max(sourceFrame.width, 1)
        canvas = DrawingCanvasView(image: image, pointScale: pointScale)

        // Leave room for the hint pill; shrink only if the capture fills the screen.
        var available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        available.origin.y += 44
        available.size.height -= 44
        let frame = sourceFrame.fitted(into: available)

        window = EditorWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        hint = HUDPanel(text: "⏎ Copy  ·  ⇧⏎ Save As…  ·  ⌘Z Undo  ·  esc Cancel")
        super.init()

        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.contentView = canvas
        window.onKey = { [weak self] action in self?.handle(action) }
        window.onResignKey = { [weak self] in self?.focusLost() }
        window.addChildWindow(hint, ordered: .above)
        hint.attach(below: frame, on: screen)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    /// Losing focus means the user moved on: copy the result so nothing is lost.
    /// Deferred so the window is never torn down inside AppKit's key-window bookkeeping,
    /// and re-checked because the Save sheet and alerts briefly take key status too (`busy`).
    private func focusLost() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.busy, self.completion != nil, !self.window.isKeyWindow else { return }
            self.copyImage()
        }
    }

    private func handle(_ action: EditorWindow.Action) {
        guard !busy else { return }
        switch action {
        case .cancel: finish(.cancelled)
        case .copy: copyImage()
        case .save: save()
        case .undo: canvas.undo()
        case .redo: canvas.redo()
        }
    }

    private func copyImage() {
        let image = canvas.renderComposite()
        Exporter.copyToClipboard(image: image, pointScale: pointScale)
        Toast.show("Copied to clipboard", on: screen)
        finish(.copied)
    }

    private func save() {
        busy = true
        let image = canvas.renderComposite()
        let name = Exporter.defaultFileName(prefix: "Screenshot", ext: "png")
        Exporter.runSavePanel(suggestedName: name, type: .png, parent: window) { [weak self] url in
            guard let self else { return }
            self.busy = false
            guard let url else { return }   // cancelled the panel: stay in the editor
            do {
                guard let data = Exporter.pngData(image, pointScale: self.pointScale) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
                Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", on: self.screen)
                self.finish(.saved(url))
            } catch {
                self.busy = true   // the alert takes focus; don't treat that as "copy and dismiss"
                NSAlert(error: error).runModal()
                self.busy = false
            }
        }
    }

    private func finish(_ outcome: EditorOutcome) {
        guard let completion else { return }
        self.completion = nil
        window.removeChildWindow(hint)
        hint.orderOut(nil)
        window.orderOut(nil)
        completion(outcome)
    }
}

final class EditorWindow: KeyableWindow {
    enum Action { case cancel, copy, save, undo, redo }
    var onKey: ((Action) -> Void)?
    var onResignKey: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 53: onKey?(.cancel)
        case 36, 76:
            onKey?(flags.contains(.shift) ? .save : .copy)
        case 6 where flags.contains(.command):   // Z
            onKey?(flags.contains(.shift) ? .redo : .undo)
        case 8 where flags.contains(.command):   // C
            onKey?(.copy)
        case 1 where flags.contains(.command):   // S
            onKey?(.save)
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // No main menu exists, so route the ⌘ combos we own through keyDown; leave the rest alone.
        if event.modifierFlags.contains(.command), [6, 8, 1].contains(Int(event.keyCode)) {   // Z, C, S
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onKey?(.cancel) }
}
