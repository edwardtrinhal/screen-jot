import AVFoundation
import AppKit
import ScreenCaptureKit

/// Records an SCStream into an H.264 .mov. Writing a compressed movie first keeps
/// memory flat; the GIF is produced afterwards by `MovieToGIF`.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue = DispatchQueue(label: "screenjot.recorder", qos: .userInitiated)
    private var firstTimestamp: CMTime?
    private var lastTimestamp: CMTime?
    private var stopped = false          // queue-confined
    private var torndown = false         // main-confined
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
        config.ignoreShadowsSingleWindow = true

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
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
    }

    func start() async throws {
        guard writer.startWriting() else {
            let error = writer.error ?? CocoaError(.fileWriteUnknown)
            discardFile()
            throw error
        }
        do {
            try await stream?.startCapture()
        } catch {
            queue.sync { stopped = true }
            if writer.status == .writing { writer.cancelWriting() }
            teardownStream()
            discardFile()
            throw error
        }
    }

    /// Stops capturing and finalizes the movie. Returns the movie URL.
    func stop() async throws -> URL {
        try? await stream?.stopCapture()
        teardownStream()
        let result: Result<Void, Error> = await withCheckedContinuation { cont in
            queue.async {
                self.stopped = true
                guard self.writer.status == .writing else {
                    cont.resume(returning: .failure(self.writer.error ?? RecordingError.noFrames))
                    return
                }
                if self.firstTimestamp == nil {
                    // Nothing was written; AVAssetWriter cannot finish an empty session cleanly.
                    self.writer.cancelWriting()
                    cont.resume(returning: .failure(RecordingError.noFrames))
                    return
                }
                self.input.markAsFinished()
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        cont.resume(returning: .success(()))
                    } else {
                        cont.resume(returning: .failure(self.writer.error ?? RecordingError.noFrames))
                    }
                }
            }
        }
        if case .failure(let error) = result {
            discardFile()
            throw error
        }
        return outputURL
    }

    /// Idempotent. Safe to call while `start()` is still in flight.
    func cancel() async {
        try? await stream?.stopCapture()
        teardownStream()
        queue.sync {
            stopped = true
            if writer.status == .writing { writer.cancelWriting() }
        }
        discardFile()
    }

    private func teardownStream() {
        guard let stream, !torndown else { return }
        torndown = true
        try? stream.removeStreamOutput(self, type: .screen)   // breaks the stream ↔ recorder retain cycle
        self.stream = nil
    }

    private func discardFile() {
        try? FileManager.default.removeItem(at: outputURL)
    }

    // MARK: SCStreamOutput (called on `queue`)

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
        } else if writer.status == .failed {
            // Disk full, temp dir unwritable, …: surface it instead of crashing on stop().
            stopped = true
            let error = writer.error ?? CocoaError(.fileWriteUnknown)
            DispatchQueue.main.async { self.onStreamError?(error) }
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
