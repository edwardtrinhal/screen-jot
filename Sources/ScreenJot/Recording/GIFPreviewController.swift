import AppKit
import UniformTypeIdentifiers

/// Shows the finished GIF where it was recorded. ⏎ copy, ⇧⏎ save, esc discard.
final class GIFPreviewController: NSObject {
    private let window: EditorWindow
    private let hint: HUDPanel
    private let gifURL: URL
    private let screen: NSScreen
    private var completion: ((EditorOutcome) -> Void)?
    private var busy = false

    init(gifURL: URL, sourceFrame: CGRect, screen: NSScreen, completion: @escaping (EditorOutcome) -> Void) {
        self.gifURL = gifURL
        self.screen = screen
        self.completion = completion

        var available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        available.origin.y += 44
        available.size.height -= 44
        let frame = sourceFrame.fitted(into: available)

        window = EditorWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        hint = HUDPanel(text: "⏎ Copy GIF  ·  ⇧⏎ Save As…  ·  esc Discard")
        super.init()

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.image = NSImage(contentsOf: gifURL)
        imageView.autoresizingMask = [.width, .height]

        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.contentView = imageView
        window.onKey = { [weak self] action in self?.handle(action) }
        window.addChildWindow(hint, ordered: .above)
        hint.attach(below: frame, on: screen)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func handle(_ action: EditorWindow.Action) {
        guard !busy else { return }
        switch action {
        case .cancel:
            try? FileManager.default.removeItem(at: gifURL)
            finish(.cancelled)
        case .copy:
            Exporter.copyToClipboard(gifAt: gifURL)
            Toast.show("GIF copied to clipboard", on: screen)
            finish(.copied)
        case .save:
            busy = true
            Exporter.runSavePanel(suggestedName: gifURL.lastPathComponent, type: .gif, parent: window) { [weak self] url in
                guard let self else { return }
                self.busy = false
                guard let url else { return }
                do {
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    try FileManager.default.copyItem(at: self.gifURL, to: url)
                    Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", on: self.screen)
                    self.finish(.saved(url))
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        case .undo, .redo:
            break
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
