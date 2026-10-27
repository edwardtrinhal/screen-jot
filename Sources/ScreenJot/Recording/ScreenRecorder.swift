import AVFoundation
import AppKit
import ScreenCaptureKit

/// Records an SCStream into an H.264 .mov. Writing a compressed movie first keeps
/// memory flat; the GIF is produced afterwards by `MovieToGIF`.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream!
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue = DispatchQueue(label: "screenjot.recorder", qos: .userInitiated)
    private var firstTimestamp: CMTime?
    private var lastTimestamp: CMTime?
    private var stopped = false
    let outputURL: URL
    var onStreamError: ((Error) -> Void)?

    /// Duration between the first and last written frame.
    var writtenDuration: TimeInterval {
        guard let f = firstTimestamp, let l = lastTimestamp else { return 0 }
        return CMTimeGetSeconds(l - f)
    }

    init(filter: SCContentFilter, sourceRect: CGRect?, outputSize: CGSize, fps: Int, outputURL: URL) throws {
        self.outputURL = outputURL
        // H.264 needs even dimensions.
        let width = max(2, Int(outputSize.width.rounded(.down)) & ~1)
        let height = max(2, Int(outputSize.height.rounded(.down)) & ~1)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if let sourceRect { config.sourceRect = sourceRect }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.queueDepth = 6
        config.scalesToFit = true

        try? FileManager.default.removeItem(at: outputURL)
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, width * height * 12),
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)

        super.init()
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        try await stream.startCapture()
    }

    /// Stops capturing and finalizes the movie. Returns the movie URL.
    func stop() async throws -> URL {
        try? await stream.stopCapture()
        let finished: Bool = await withCheckedContinuation { cont in
            queue.async {
                self.stopped = true
                if self.firstTimestamp == nil {
                    // Nothing was written; AVAssetWriter can't finish an empty session cleanly.
                    self.writer.cancelWriting()
                    cont.resume(returning: false)
                    return
                }
                self.input.markAsFinished()
                self.writer.finishWriting { cont.resume(returning: self.writer.status == .completed) }
            }
        }
        if !finished { throw RecordingError.noFrames }
        return outputURL
    }

    func cancel() async {
        try? await stream.stopCapture()
        queue.sync {
            stopped = true
            writer.cancelWriting()
        }
        try? FileManager.default.removeItem(at: outputURL)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !stopped, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        let pts = sampleBuffer.presentationTimeStamp
        if firstTimestamp == nil {
            firstTimestamp = pts
            writer.startSession(atSourceTime: pts)
        }
        guard input.isReadyForMoreMediaData else { return }
        if adaptor.append(pixelBuffer, withPresentationTime: pts) {
            lastTimestamp = pts
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onStreamError?(error) }
    }
}

enum RecordingError: LocalizedError {
    case noFrames

    var errorDescription: String? {
        switch self {
        case .noFrames: return "No frames were captured."
        }
    }
}
