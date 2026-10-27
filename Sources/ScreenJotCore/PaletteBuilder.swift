import Foundation

/// Accumulates color statistics from sampled frames and produces a GIF palette.
///
/// Strategy:
///  - Track exact distinct colors while there are few of them. Screen recordings of
///    UI are often well under 256 colors, in which case the palette is exact and no
///    dithering is needed.
///  - Otherwise fall back to a weighted median cut over a 6-bit-per-channel histogram
///    (262,144 bins), averaging the true 8-bit colors inside each final box.
public final class PaletteBuilder {
    public struct Result {
        public let colors: [PackedRGB]
        /// True when every sampled color is present verbatim in `colors`.
        public let isExact: Bool
    }

    private static let bits = 6
    private static let binCount = 1 << (bits * 3)
    private static let exactLimit = 4096

    private var counts = [UInt32](repeating: 0, count: PaletteBuilder.binCount)
    private var sumR = [UInt64](repeating: 0, count: PaletteBuilder.binCount)
    private var sumG = [UInt64](repeating: 0, count: PaletteBuilder.binCount)
    private var sumB = [UInt64](repeating: 0, count: PaletteBuilder.binCount)
    private var exactColors = Set<PackedRGB>()
    private var exactOverflowed = false
    public private(set) var sampleCount = 0

    public init() {}

    /// Samples every `step`-th pixel in both directions.
    public func addSamples(from image: BGRAImage, step: Int = 2) {
        let step = max(1, step)
        image.pixels.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            var y = 0
            while y < image.height {
                let row = base + y * image.bytesPerRow
                var x = 0
                while x < image.width {
                    let p = row + x * 4
                    let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
                    add(r: r, g: g, b: b)
                    x += step
                }
                y += step
            }
        }
    }

    @inline(__always) private func add(r: Int, g: Int, b: Int) {
        let shift = 8 - PaletteBuilder.bits
        let bin = (r >> shift) << (PaletteBuilder.bits * 2) | (g >> shift) << PaletteBuilder.bits | (b >> shift)
        counts[bin] &+= 1
        sumR[bin] &+= UInt64(r)
        sumG[bin] &+= UInt64(g)
        sumB[bin] &+= UInt64(b)
        sampleCount += 1
        if !exactOverflowed {
            exactColors.insert(pack(r, g, b))
            if exactColors.count > PaletteBuilder.exactLimit {
                exactOverflowed = true
                exactColors.removeAll()
            }
        }
    }

    public func build(maxColors: Int = 255) -> Result {
        precondition(maxColors >= 2 && maxColors <= 256)
        if sampleCount == 0 { return Result(colors: [0], isExact: true) }
        if !exactOverflowed && exactColors.count <= maxColors {
            return Result(colors: exactColors.sorted(), isExact: true)
        }
        return Result(colors: medianCut(maxColors: maxColors), isExact: false)
    }

    // MARK: - Median cut

    private struct Bin {
        var r: Int, g: Int, b: Int   // 6-bit coordinates
        var count: Int
        var index: Int
    }

    private struct Box {
        var range: Range<Int>
        var count: Int
        var rMin: Int, rMax: Int, gMin: Int, gMax: Int, bMin: Int, bMax: Int

        var longestSide: Int { max(rMax - rMin, gMax - gMin, bMax - bMin) }
        var splittable: Bool { range.count > 1 && longestSide > 0 }
        var score: Int { count * (longestSide + 1) }
    }

    private func makeBox(_ bins: [Bin], _ range: Range<Int>) -> Box {
        var box = Box(range: range, count: 0, rMin: 64, rMax: -1, gMin: 64, gMax: -1, bMin: 64, bMax: -1)
        for i in range {
            let bin = bins[i]
            box.count += bin.count
            box.rMin = min(box.rMin, bin.r); box.rMax = max(box.rMax, bin.r)
            box.gMin = min(box.gMin, bin.g); box.gMax = max(box.gMax, bin.g)
            box.bMin = min(box.bMin, bin.b); box.bMax = max(box.bMax, bin.b)
        }
        return box
    }

    private func medianCut(maxColors: Int) -> [PackedRGB] {
        let bits = PaletteBuilder.bits
        let mask = (1 << bits) - 1
        var bins: [Bin] = []
        bins.reserveCapacity(4096)
        for i in 0..<PaletteBuilder.binCount where counts[i] > 0 {
            bins.append(Bin(r: (i >> (bits * 2)) & mask, g: (i >> bits) & mask, b: i & mask, count: Int(counts[i]), index: i))
        }

        var boxes = [makeBox(bins, 0..<bins.count)]
        while boxes.count < maxColors {
            var bestIndex = -1
            var bestScore = -1
            for (i, box) in boxes.enumerated() where box.splittable && box.score > bestScore {
                bestScore = box.score
                bestIndex = i
            }
            if bestIndex < 0 { break }
            let box = boxes[bestIndex]

            let rRange = box.rMax - box.rMin, gRange = box.gMax - box.gMin, bRange = box.bMax - box.bMin
            let slice = bins[box.range]
            let sorted: [Bin]
            if rRange >= gRange && rRange >= bRange {
                sorted = slice.sorted { $0.r < $1.r }
            } else if gRange >= bRange {
                sorted = slice.sorted { $0.g < $1.g }
            } else {
                sorted = slice.sorted { $0.b < $1.b }
            }
            bins.replaceSubrange(box.range, with: sorted)

            // Weighted median, keeping both halves non-empty.
            let half = box.count / 2
            var acc = 0
            var split = box.range.lowerBound
            for i in box.range {
                acc += bins[i].count
                if acc >= half { split = i + 1; break }
            }
            split = min(max(split, box.range.lowerBound + 1), box.range.upperBound - 1)

            boxes[bestIndex] = makeBox(bins, box.range.lowerBound..<split)
            boxes.append(makeBox(bins, split..<box.range.upperBound))
        }

        var colors: [PackedRGB] = []
        colors.reserveCapacity(boxes.count)
        for box in boxes {
            var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, n: UInt64 = 0
            for i in box.range {
                let idx = bins[i].index
                r += sumR[idx]; g += sumG[idx]; b += sumB[idx]; n += UInt64(counts[idx])
            }
            guard n > 0 else { continue }
            colors.append(pack(Int(r / n), Int(g / n), Int(b / n)))
        }
        return Array(Set(colors)).sorted()
    }
}
