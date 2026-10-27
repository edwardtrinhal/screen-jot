import Foundation

/// A packed 8-bit BGRA bitmap. This is the native layout of CVPixelBuffers and
/// CGBitmapContexts on macOS, so frames can be copied in without conversion.
public struct BGRAImage {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0)
        precondition(bytesPerRow >= width * 4)
        precondition(pixels.count >= bytesPerRow * height)
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    /// Builds an image by calling `fill` for every pixel. Used by tests and tools.
    public init(width: Int, height: Int, fill: (_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8)) {
        var px = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = fill(x, y)
                let o = (y * width + x) * 4
                px[o] = b; px[o + 1] = g; px[o + 2] = r; px[o + 3] = 255
            }
        }
        self.init(width: width, height: height, bytesPerRow: width * 4, pixels: px)
    }
}

/// 0x00RRGGBB
public typealias PackedRGB = UInt32

@inline(__always) func pack(_ r: Int, _ g: Int, _ b: Int) -> PackedRGB {
    PackedRGB(r) << 16 | PackedRGB(g) << 8 | PackedRGB(b)
}
