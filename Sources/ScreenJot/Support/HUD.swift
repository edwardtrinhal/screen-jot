import AppKit

/// Borderless window that can become key even without a title bar.
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Small translucent pill used for hints under the editor and for toasts.
final class HUDPanel: NSPanel {
    let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
        ])
        contentView = effect
        setText(text)
    }

    func setText(_ text: String) {
        label.attributedStringValue = HUDPanel.styled(text)
        let size = label.attributedStringValue.size()
        setContentSize(NSSize(width: ceil(size.width) + 28, height: ceil(size.height) + 16))
    }

    /// Renders "⏎ Copy" style hints: key glyphs bold, separators dimmed.
    static func styled(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.92)]
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let dim: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.4)]
        for (i, part) in text.components(separatedBy: "  ·  ").enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "   ·   ", attributes: dim)) }
            let words = part.split(separator: " ", maxSplits: 1).map(String.init)
            if words.count == 2, words[0].unicodeScalars.allSatisfy({ !CharacterSet.letters.contains($0) }) || words[0] == "esc" || words[0] == "Tab" {
                result.append(NSAttributedString(string: words[0] + " ", attributes: key))
                result.append(NSAttributedString(string: words[1], attributes: base))
            } else {
                result.append(NSAttributedString(string: part, attributes: base))
            }
        }
        return result
    }

    /// Positions the panel centered horizontally below `frame`, flipping above or inside when there is no room.
    func attach(below frame: CGRect, on screen: NSScreen, gap: CGFloat = 10) {
        let size = self.frame.size
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.minY - gap - size.height)
        let visible = screen.visibleFrame
        if origin.y < visible.minY {
            origin.y = frame.maxY + gap
            if origin.y + size.height > visible.maxY {
                origin.y = frame.minY + gap   // inside, bottom edge
            }
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        setFrameOrigin(origin)
    }
}

enum Toast {
    static func show(_ text: String, on screen: NSScreen? = NSScreen.main, duration: TimeInterval = 1.1) {
        guard let screen else { return }
        let panel = HUDPanel(text: text)
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 80))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
    }
}
