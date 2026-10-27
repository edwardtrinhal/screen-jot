import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ScreenJotCore

/// Writes a short synthetic H.264 movie with uneven frame timing (like SCStream, which
/// only delivers frames when content changes), converts it to GIF and checks the result.
func runMovieToGIFTest(check: (Bool, String) -> Void) async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("screenjot-selftest-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let movieURL = dir.appendingPathComponent("in.mov")
    let gifURL = dir.appendingPathComponent("out.gif")

    let w = 320, h = 180
    do {
        let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { check(false, "writer start: \(String(describing: writer.error))"); return }
        writer.startSession(atSourceTime: .zero)

        // Frame times in seconds: a burst, a pause, then regular 15 fps.
        let times: [Double] = [0, 0.0667, 0.1333, 1.0, 1.0667, 1.1333, 1.2, 1.2667]
        for (i, t) in times.enumerated() {
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            guard let pb else { check(false, "pixel buffer"); return }
            CVPixelBufferLockBaseAddress(pb, [])
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<h { for x in 0..<w {
                let o = y * stride + x * 4
                let inBox = x >= 20 + i * 30 && x < 60 + i * 30 && y >= 60 && y < 120
                base[o] = inBox ? 40 : 200; base[o + 1] = inBox ? 60 : 200; base[o + 2] = inBox ? 230 : 200; base[o + 3] = 255
            }}
            CVPixelBufferUnlockBaseAddress(pb, [])
            while !input.isReadyForMoreMediaData { usleep(1000) }
            check(adaptor.append(pb, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)), "append frame \(i)")
        }
        input.markAsFinished()
        await writer.finishWriting()
        check(writer.status == .completed, "synthetic movie written (\(writer.status.rawValue))")
    } catch {
        check(false, "writer error \(error)")
        return
    }

    do {
        var last = 0.0
        let start = Date()
        try await MovieToGIF.convert(movieURL: movieURL, to: gifURL, fps: 15, totalDuration: 1.4) { last = $0 }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        check(last == 1, "progress reaches 1.0")
        let data = try Data(contentsOf: gifURL)
        check(data.count > 100, "gif written (\(data.count) bytes, \(ms) ms)")
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { check(false, "gif decodes"); return }
        let n = CGImageSourceGetCount(src)
        check(n == 8, "8 frames survive (got \(n))")
        var delays: [Double] = []
        for i in 0..<n {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            delays.append(gif?[kCGImagePropertyGIFDelayTime] as? Double ?? -1)
        }
        if delays.count == 8 {
            check(abs(delays[0] - 0.07) < 0.011, "burst frame delay ~0.07 (\(delays[0]))")
            check(abs(delays[2] - 0.87) < 0.011, "pause preserved as long delay (\(delays[2]))")
            check(abs(delays[7] - 0.13) < 0.011, "last frame delay from total duration (\(delays[7]))")
        }
        if let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            check(img.width == w && img.height == h, "gif canvas is \(w)x\(h)")
        }
    } catch {
        check(false, "conversion error \(error)")
    }
}
