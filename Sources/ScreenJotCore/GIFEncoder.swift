import Foundation

/// Streaming animated GIF encoder with a global palette, inter-frame differencing
/// (unchanged pixels become transparent, frames cropped to the changed bounding box)
/// and merging of identical consecutive frames into longer delays.
public final class GIFEncoder {
    public struct Options {
        /// 0 = loop forever.
        public var loopCount: Int = 0
        /// Ordered (Bayer 4x4) dithering. Ignored when the palette is exact.
        public var dither: Bool = true
        public init() {}
    }

    public let width: Int
    public let height: Int
    private let mapper: ColorMapper
    private let dither: Bool
    private let transparentIndex: UInt8 = 255
    private var out = Data()
    private var lzw = LZWEncoder()
    private var canvas: [UInt8]?       // palette indices of the last logical frame
    private var pending: PendingFrame?
    public private(set) var frameCount = 0
    private var finished = false

    private struct PendingFrame {
        var x: Int, y: Int, w: Int, h: Int
        var indices: [UInt8]
        var delay: Int
        var transparent: Bool
    }

    // Bayer 4x4 thresholds scaled to a small +-4 level spread.
    private static let bayer: [Int] = {
        let m = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        return m.map { ($0 * 8) / 16 - 4 }
    }()

    public init(width: Int, height: Int, palette: PaletteBuilder.Result, options: Options = Options()) {
        precondition(width > 0 && width <= 65535 && height > 0 && height <= 65535)
        self.width = width
        self.height = height
        self.mapper = ColorMapper(palette: Array(palette.colors.prefix(255)))
        self.dither = options.dither && !palette.isExact
        writeHeader(loopCount: options.loopCount)
    }

    /// Adds a frame. `delayCentiseconds` is how long this frame is shown; values below 2
    /// are treated as 10 by most viewers, so callers should merge faster frames.
    public func addFrame(_ image: BGRAImage, delayCentiseconds: Int) {
        precondition(!finished)
        precondition(image.width == width && image.height == height, "frame size mismatch")
        let delay = max(0, min(65535, delayCentiseconds))
        let indices = quantize(image)

        guard let previous = canvas else {
            pending = PendingFrame(x: 0, y: 0, w: width, h: height, indices: indices, delay: delay, transparent: false)
            canvas = indices
            return
        }

        // Bounding box of changed pixels.
        var minX = width, minY = height, maxX = -1, maxY = -1
        indices.withUnsafeBufferPointer { cur in
            previous.withUnsafeBufferPointer { prev in
                for y in 0..<height {
                    let row = y * width
                    var x = 0
                    var rowChanged = false
                    while x < width {
                        if cur[row + x] != prev[row + x] {
                            rowChanged = true
                            if x < minX { minX = x }
                            if x > maxX { maxX = x }
                        }
                        x += 1
                    }
                    if rowChanged {
                        if y < minY { minY = y }
                        maxY = y
                    }
                }
            }
        }

        if maxX < 0 {
            // Identical frame: extend the previous one.
            pending?.delay = min(65535, (pending?.delay ?? 0) + delay)
            return
        }

        flushPending()
        let w = maxX - minX + 1, h = maxY - minY + 1
        var sub = [UInt8](repeating: 0, count: w * h)
        sub.withUnsafeMutableBufferPointer { dst in
            indices.withUnsafeBufferPointer { cur in
                previous.withUnsafeBufferPointer { prev in
                    for y in 0..<h {
                        let srcRow = (minY + y) * width + minX
                        let dstRow = y * w
                        for x in 0..<w {
                            let c = cur[srcRow + x]
                            dst[dstRow + x] = c == prev[srcRow + x] ? transparentIndex : c
                        }
                    }
                }
            }
        }
        pending = PendingFrame(x: minX, y: minY, w: w, h: h, indices: sub, delay: delay, transparent: true)
        canvas = indices
    }

    public func finish() -> Data {
        precondition(!finished)
        flushPending()
        out.append(0x3B)
        finished = true
        return out
    }

    // MARK: - Internals

    private func quantize(_ image: BGRAImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height)
        let dither = self.dither
        let bayer = GIFEncoder.bayer
        result.withUnsafeMutableBufferPointer { dst in
            image.pixels.withUnsafeBufferPointer { src in
                let base = src.baseAddress!
                for y in 0..<height {
                    let row = base + y * image.bytesPerRow
                    let outRow = y * width
                    for x in 0..<width {
                        let p = row + x * 4
                        var b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
                        if dither {
                            let t = bayer[(y & 3) << 2 | (x & 3)]
                            r = min(255, max(0, r + t))
                            g = min(255, max(0, g + t))
                            b = min(255, max(0, b + t))
                        }
                        dst[outRow + x] = mapper.index(r: r, g: g, b: b)
                    }
                }
            }
        }
        return result
    }

    private func writeHeader(loopCount: Int) {
        out.append(contentsOf: Array("GIF89a".utf8))
        appendUInt16(width)
        appendUInt16(height)
        out.append(0xF7)        // global color table, 8 bits/channel, 256 entries
        out.append(0)           // background color index
        out.append(0)           // pixel aspect ratio
        let colors = mapper.palette
        for i in 0..<256 {
            if i < colors.count {
                let c = colors[i]
                out.append(UInt8((c >> 16) & 0xFF)); out.append(UInt8((c >> 8) & 0xFF)); out.append(UInt8(c & 0xFF))
            } else {
                out.append(0); out.append(0); out.append(0)
            }
        }
        // Netscape looping extension.
        out.append(contentsOf: [0x21, 0xFF, 0x0B])
        out.append(contentsOf: Array("NETSCAPE2.0".utf8))
        out.append(contentsOf: [0x03, 0x01])
        appendUInt16(max(0, min(65535, loopCount)))
        out.append(0)
    }

    private func flushPending() {
        guard let f = pending else { return }
        pending = nil
        // Graphic control extension.
        out.append(contentsOf: [0x21, 0xF9, 0x04])
        let disposal: UInt8 = 1 << 2   // do not dispose
        out.append(disposal | (f.transparent ? 1 : 0))
        appendUInt16(f.delay)
        out.append(f.transparent ? transparentIndex : 0)
        out.append(0)
        // Image descriptor.
        out.append(0x2C)
        appendUInt16(f.x); appendUInt16(f.y); appendUInt16(f.w); appendUInt16(f.h)
        out.append(0)   // no local color table, not interlaced
        lzw.encode(f.indices, minCodeSize: 8, into: &out)
        frameCount += 1
    }

    @inline(__always) private func appendUInt16(_ v: Int) {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF))
    }
}
