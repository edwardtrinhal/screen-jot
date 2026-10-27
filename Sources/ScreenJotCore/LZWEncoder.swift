import Foundation

/// GIF-flavoured LZW (variable code width 3...12 bits, clear/EOI codes, 255-byte
/// sub-blocks). The string table is a direct-mapped (prefix, byte) -> code array with
/// generation stamps, so a table reset is O(1).
final class LZWEncoder {
    private static let tableSize = 4096 * 256
    private var table = [UInt32](repeating: 0, count: LZWEncoder.tableSize)
    private var generation: UInt32 = 1

    // Bit/block output state.
    private var out = Data()
    private var accum: UInt32 = 0
    private var accumBits = 0
    private var block = [UInt8](repeating: 0, count: 256)
    private var blockLen = 0

    // Code state.
    private var nBits = 0
    private var initBits = 0
    private var maxCode = 0
    private var freeEntry = 0
    private var clearCode = 0
    private var eoiCode = 0
    private var clearFlag = false

    init() {}

    func encode(_ indices: [UInt8], minCodeSize: Int, into output: inout Data) {
        out = Data()
        out.reserveCapacity(indices.count / 4 + 64)
        accum = 0; accumBits = 0; blockLen = 0

        let minCodeSize = max(2, minCodeSize)
        output.append(UInt8(minCodeSize))
        initBits = minCodeSize + 1
        nBits = initBits
        maxCode = (1 << nBits) - 1
        clearCode = 1 << minCodeSize
        eoiCode = clearCode + 1
        freeEntry = clearCode + 2
        clearFlag = false
        resetTable()

        emit(clearCode)
        indices.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress, buf.count > 0 else { return }
            var prefix = Int(base[0])
            var i = 1
            let n = buf.count
            while i < n {
                let c = Int(base[i])
                i += 1
                let key = prefix << 8 | c
                let entry = table[key]
                if entry >> 12 == generation {
                    prefix = Int(entry & 0xFFF)
                    continue
                }
                emit(prefix)
                if freeEntry < 4096 {
                    table[key] = generation << 12 | UInt32(freeEntry)
                    freeEntry += 1
                } else {
                    // Order matters: the flag must be set before emitting the clear code so
                    // the code width resets immediately after it, matching decoders.
                    resetTable()
                    freeEntry = clearCode + 2
                    clearFlag = true
                    emit(clearCode)
                }
                prefix = c
            }
            emit(prefix)
        }
        emit(eoiCode)
        flush()
        output.append(out)
    }

    private func resetTable() {
        generation &+= 1
        if generation >= (1 << 19) {
            table.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            generation = 1
        }
    }

    @inline(__always) private func emit(_ code: Int) {
        accum |= UInt32(code) << UInt32(accumBits)
        accumBits += nBits
        while accumBits >= 8 {
            writeByte(UInt8(accum & 0xFF))
            accum >>= 8
            accumBits -= 8
        }
        if freeEntry > maxCode || clearFlag {
            if clearFlag {
                nBits = initBits
                maxCode = (1 << nBits) - 1
                clearFlag = false
            } else {
                nBits += 1
                maxCode = nBits == 12 ? 4096 : (1 << nBits) - 1
            }
        }
    }

    @inline(__always) private func writeByte(_ b: UInt8) {
        block[blockLen] = b
        blockLen += 1
        if blockLen == 255 {
            out.append(255)
            block.withUnsafeBufferPointer { out.append($0.baseAddress!, count: 255) }
            blockLen = 0
        }
    }

    private func flush() {
        if accumBits > 0 {
            writeByte(UInt8(accum & 0xFF))
            accum = 0; accumBits = 0
        }
        if blockLen > 0 {
            out.append(UInt8(blockLen))
            block.withUnsafeBufferPointer { out.append($0.baseAddress!, count: blockLen) }
            blockLen = 0
        }
        out.append(0)   // block terminator
    }
}
