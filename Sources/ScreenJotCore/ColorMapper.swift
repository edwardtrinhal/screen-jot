import Foundation

/// Maps RGB colors to the nearest palette index. A 16 MB direct-mapped cache keyed by
/// the full 24-bit color makes repeated lookups (the common case for screen content)
/// a single array read, while guaranteeing exact results for colors in the palette.
public final class ColorMapper {
    public let palette: [PackedRGB]
    private var cache = [UInt8](repeating: 0, count: 1 << 24)   // 0 = unknown, else index + 1
    private let pr: [Int], pg: [Int], pb: [Int]

    public init(palette: [PackedRGB]) {
        precondition(!palette.isEmpty && palette.count <= 255)
        self.palette = palette
        pr = palette.map { Int(($0 >> 16) & 0xFF) }
        pg = palette.map { Int(($0 >> 8) & 0xFF) }
        pb = palette.map { Int($0 & 0xFF) }
    }

    @inline(__always)
    public func index(r: Int, g: Int, b: Int) -> UInt8 {
        let key = r << 16 | g << 8 | b
        let cached = cache[key]
        if cached != 0 { return cached &- 1 }
        let found = nearest(r: r, g: g, b: b)
        cache[key] = found &+ 1
        return found
    }

    private func nearest(r: Int, g: Int, b: Int) -> UInt8 {
        var best = 0
        var bestDist = Int.max
        for i in 0..<palette.count {
            let dr = pr[i] - r, dg = pg[i] - g, db = pb[i] - b
            // Perceptual-ish weighting (green dominates luminance).
            let d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
            if d < bestDist { bestDist = d; best = i; if d == 0 { break } }
        }
        return UInt8(best)
    }
}
