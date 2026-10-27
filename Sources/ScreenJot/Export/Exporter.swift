import AppKit
import UniformTypeIdentifiers

enum Exporter {
    // MARK: PNG

    static func pngData(_ image: CGImage, pointScale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72 * pointScale
        let props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func copyToClipboard(image: CGImage, pointScale: CGFloat) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        if let png = pngData(image, pointScale: pointScale) {
            item.setData(png, forType: .png)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pb.writeObjects([item])
    }

    // MARK: GIF

    static func copyToClipboard(gifAt url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
        pb.writeObjects([item])
    }

    // MARK: Save panel

    static func defaultFileName(prefix: String, ext: String) -> String {
        "\(prefix) \(TempFiles.timestamp()).\(ext)"
    }

    /// Runs the Save As panel. Calls back with the chosen URL or nil when cancelled.
    static func runSavePanel(suggestedName: String, type: UTType, parent: NSWindow?, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = Preferences.lastSaveDirectory
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            Preferences.lastSaveDirectory = url.deletingLastPathComponent()
            completion(url)
        }
        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }
}
