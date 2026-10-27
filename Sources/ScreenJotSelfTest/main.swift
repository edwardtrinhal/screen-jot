import Foundation
import CoreGraphics
import ImageIO
import ScreenJotCore

// Minimal self-test harness (Command Line Tools ship no XCTest).
var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if cond() { print("  ok   \(message)") } else { failures += 1; print("  FAIL \(message)  (\(file):\(line))") }
}

func decode(_ data: Data) -> (frames: [CGImage], delays: [Double]) {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return ([], []) }
    var frames: [CGImage] = [], delays: [Double] = []
    for i in 0..<CGImageSourceGetCount(src) {
        guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
        frames.append(img)
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        delays.append(gif?[kCGImagePropertyGIFDelayTime] as? Double ?? -1)
    }
    return (frames, delays)
}

func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
    return (Int(px[0]), Int(px[1]), Int(px[2]))
}

print("Exact palette, frame differencing, delay merging")
do {
    let w = 64, h = 40
    func frame(_ t: Int) -> BGRAImage {
        BGRAImage(width: w, height: h) { x, y in
            if x >= 10 + t * 5 && x < 20 + t * 5 && y >= 10 && y < 20 { return (255, 0, 0) }
            return y < 20 ? (20, 20, 20) : (240, 240, 240)
        }
    }
    let pb = PaletteBuilder()
    for t in 0..<4 { pb.addSamples(from: frame(t), step: 1) }
    let pal = pb.build()
    check(pal.isExact, "palette is exact for 3-color content")
    check(pal.colors.count == 3, "palette has 3 colors (got \(pal.colors.count))")

    let enc = GIFEncoder(width: w, height: h, palette: pal)
    enc.addFrame(frame(0), delayCentiseconds: 7)
    enc.addFrame(frame(0), delayCentiseconds: 7)   // identical: merged
    enc.addFrame(frame(1), delayCentiseconds: 7)
    enc.addFrame(frame(2), delayCentiseconds: 6)
    let data = enc.finish()
    check(enc.frameCount == 3, "identical frame merged (frameCount=\(enc.frameCount))")
    check(data.starts(with: Array("GIF89a".utf8)), "GIF89a header")
    check(data.last == 0x3B, "trailer present")

    let (frames, delays) = decode(data)
    check(frames.count == 3, "ImageIO decodes 3 frames (got \(frames.count))")
    check(frames.allSatisfy { $0.width == w && $0.height == h }, "decoded frames have canvas size")
    if delays.count == 3 {
        check(abs(delays[0] - 0.14) < 0.005, "merged delay is 0.14 s (got \(delays[0]))")
        check(abs(delays[1] - 0.07) < 0.005, "second delay 0.07 s (got \(delays[1]))")
    }
    if frames.count == 3 {
        let p0 = pixel(frames[0], 12, 12), p1 = pixel(frames[1], 12, 12), p1b = pixel(frames[1], 17, 12)
        check(p0 == (255, 0, 0), "frame 0 red square at (12,12) \(p0)")
        check(p1 == (20, 20, 20), "frame 1 background where square moved away \(p1)")
        check(p1b == (255, 0, 0), "frame 1 red square at new position \(p1b)")
        let p2 = pixel(frames[2], 5, 30)
        check(p2 == (240, 240, 240), "lower half light grey in frame 2 \(p2)")
    }
}

print("Median-cut palette on a gradient")
do {
    let w = 200, h = 120
    let img = BGRAImage(width: w, height: h) { x, y in (UInt8(x * 255 / (w - 1)), UInt8(y * 255 / (h - 1)), 128) }
    let pb = PaletteBuilder()
    pb.addSamples(from: img, step: 1)
    let pal = pb.build()
    check(!pal.isExact, "gradient palette is not exact")
    check(pal.colors.count > 200 && pal.colors.count <= 255, "palette size within bounds (got \(pal.colors.count))")
    let enc = GIFEncoder(width: w, height: h, palette: pal)
    enc.addFrame(img, delayCentiseconds: 10)
    let data = enc.finish()
    let (frames, _) = decode(data)
    check(frames.count == 1, "single frame decodes")
    if let f = frames.first {
        var maxErr = 0
        for (x, y) in [(0, 0), (199, 0), (0, 119), (199, 119), (100, 60), (50, 90)] {
            let p = pixel(f, x, y)
            let e = (x * 255 / (w - 1), y * 255 / (h - 1), 128)
            maxErr = max(maxErr, abs(p.r - e.0), abs(p.g - e.1), abs(p.b - e.2))
        }
        check(maxErr <= 24, "quantization error within tolerance (max \(maxErr))")
    }
}

print("LZW stress: noisy frame forces table resets")
do {
    let w = 300, h = 200
    var seed: UInt32 = 12345
    func rnd() -> UInt8 { seed = seed &* 1664525 &+ 1013904223; return UInt8(truncatingIfNeeded: seed >> 24) }
    let img = BGRAImage(width: w, height: h) { _, _ in (rnd(), rnd(), rnd()) }
    let pb = PaletteBuilder(); pb.addSamples(from: img, step: 1)
    let pal = pb.build()
    var opts = GIFEncoder.Options(); opts.dither = false   // deterministic mapping for exact comparison
    let enc = GIFEncoder(width: w, height: h, palette: pal, options: opts)
    let start = Date()
    enc.addFrame(img, delayCentiseconds: 10)
    enc.addFrame(img, delayCentiseconds: 10)
    let data = enc.finish()
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    let (frames, delays) = decode(data)
    check(frames.count == 1, "noise frame decodes (count \(frames.count), \(data.count) bytes, \(ms) ms)")
    check(delays.first.map { abs($0 - 0.2) < 0.005 } ?? false, "duplicate noise frame merged into 0.2 s")
    if let f = frames.first {
        // Compare a handful of pixels against the encoder's own palette mapping.
        let mapper = ColorMapper(palette: pal.colors)
        var mismatches = 0
        for i in stride(from: 0, to: w * h, by: 997) {
            let x = i % w, y = i / w
            let o = y * img.bytesPerRow + x * 4
            let (b, g, r) = (Int(img.pixels[o]), Int(img.pixels[o + 1]), Int(img.pixels[o + 2]))
            let p = pixel(f, x, y)
            let idx = Int(mapper.index(r: r, g: g, b: b))
            let c = pal.colors[idx]
            let (cr, cg, cb) = (Int((c >> 16) & 0xFF), Int((c >> 8) & 0xFF), Int(c & 0xFF))
            if p.r != cr || p.g != cg || p.b != cb { mismatches += 1 }
        }
        check(mismatches == 0, "decoded pixels exactly match palette mapping (mismatches \(mismatches))")
    }
}

if let outPath = CommandLine.arguments.dropFirst().first {
    let w = 160, h = 90
    let pb = PaletteBuilder()
    var frames: [BGRAImage] = []
    for t in 0..<30 {
        frames.append(BGRAImage(width: w, height: h) { x, y in
            let cx = 20 + t * 4, cy = 45
            let d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if d < 150 { return (255, 59, 48) }
            return (UInt8(30 + x / 2), UInt8(30 + y), 60)
        })
    }
    for f in frames { pb.addSamples(from: f) }
    let enc = GIFEncoder(width: w, height: h, palette: pb.build())
    for f in frames { enc.addFrame(f, delayCentiseconds: 7) }
    try! enc.finish().write(to: URL(fileURLWithPath: outPath))
    print("wrote sample GIF to \(outPath)")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
