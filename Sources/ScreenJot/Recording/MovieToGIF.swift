import AVFoundation
import CoreVideo
import Foundation
import ScreenJotCore

/// Two-pass conversion: sample frames for the palette, then encode every frame with the
/// real inter-frame timing from the movie. Memory stays bounded to one frame at a time.
enum MovieToGIF {
    static func convert(movieURL: URL, to gifURL: URL, fps: Int, totalDuration: TimeInterval,
                        progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: movieURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingError.conversionFailed("no video track")
        }
        let size = try await track.load(.naturalSize)
        let width = Int(size.width), height = Int(size.height)
        let duration = max(totalDuration, CMTimeGetSeconds(try await asset.load(.duration)))
        let estimatedFrames = max(1, Int(duration * Double(fps)))
        let paletteStride = max(1, estimatedFrames / 24)

        // Pass 1: palette.
        let builder = PaletteBuilder()
        var index = 0
        try readFrames(asset: asset, track: track) { image, _ in
            if index % paletteStride == 0 { builder.addSamples(from: image, step: 2) }
            index += 1
            progress(0.25 * Double(index) / Double(estimatedFrames))
            return true
        }
        let frameTotal = max(1, index)
        let palette = builder.build(maxColors: 255)

        // Pass 2: encode with real timing.
        let encoder = GIFEncoder(width: width, height: height, palette: palette)
        var pendingImage: BGRAImage?
        var pendingStartCS = 0
        var count = 0
        try readFrames(asset: asset, track: track) { image, seconds in
            let cs = Int((seconds * 100).rounded())
            if let prev = pendingImage {
                let delay = cs - pendingStartCS
                if delay >= 2 {
                    encoder.addFrame(prev, delayCentiseconds: delay)
                    pendingStartCS = cs
                }
                // delay < 2: this frame arrived too soon for GIF timing, drop the older one.
            }
            pendingImage = image
            count += 1
            progress(0.25 + 0.7 * Double(count) / Double(frameTotal))
            return true
        }
        if let last = pendingImage {
            let totalCS = Int((duration * 100).rounded())
            let remaining = totalCS - pendingStartCS
            encoder.addFrame(last, delayCentiseconds: max(100 / fps, min(remaining, 3000)))
        }
        let data = encoder.finish()
        guard encoder.frameCount > 0 else { throw RecordingError.conversionFailed("no frames") }
        try data.write(to: gifURL, options: .atomic)
        progress(1)
    }

    /// Iterates decoded frames in presentation order. The callback returns false to stop early.
    private static func readFrames(asset: AVAsset, track: AVAssetTrack, _ body: (BGRAImage, TimeInterval) -> Bool) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RecordingError.conversionFailed("reader failed") }
        var first: CMTime?
        while let sample = output.copyNextSampleBuffer() {
            guard let pb = sample.imageBuffer else { continue }
            let pts = sample.presentationTimeStamp
            if first == nil { first = pts }
            let seconds = CMTimeGetSeconds(pts - first!)
            if !body(bgraImage(from: pb), seconds) { break }
        }
        reader.cancelReading()
        if reader.status == .failed { throw reader.error ?? RecordingError.conversionFailed("decode failed") }
    }

    private static func bgraImage(from pb: CVPixelBuffer) -> BGRAImage {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let width = CVPixelBufferGetWidth(pb), height = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let pixels = [UInt8](unsafeUninitializedCapacity: stride * height) { buf, initialized in
            buf.baseAddress!.update(from: base, count: stride * height)
            initialized = stride * height
        }
        return BGRAImage(width: width, height: height, bytesPerRow: stride, pixels: pixels)
    }
}
