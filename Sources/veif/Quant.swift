import Foundation

func quantizeBlock(block: UnsafeMutablePointer<Int16>, size: Int, scale: Int) {
    var baseShift = scale
    if baseShift < 0 {
        baseShift = 0
    }

    let half = size / 2
    var quarter = size / 4
    if size < 16 {
        quarter = 0
    }

    for y in 0..<size {
        for x in 0..<size {
            // Default: High Frequency (Level 1)
            var shift = baseShift + 5

            if x < half && y < half {
                // Level 2 Subband
                shift = baseShift + 2
                if 0 < quarter && x < quarter && y < quarter {
                    // LL2 (Lowest Frequency)
                    shift = baseShift
                }
            }
            if shift < 0 {
                shift = 0
            }

            if shift == 0 {
                continue
            }

            let offset = y * size + x
            let v = Int32(block[offset])
            let off = Int32(1 << (shift - 1))

            if 0 <= v {
                block[offset] = Int16((v + off) >> shift)
            } else {
                block[offset] = Int16(-((-v + off) >> shift))
            }
        }
    }
}

func dequantizeBlock(block: UnsafeMutableBufferPointer<Int16>, size: Int, scale: Int) {
    var baseShift = scale
    if baseShift < 0 {
        baseShift = 0
    }

    let half = size / 2
    var quarter = size / 4
    if size < 16 {
        quarter = 0
    }

    for y in 0..<size {
        for x in 0..<size {
            var shift = baseShift + 5
            if x < half && y < half {
                shift = baseShift + 2
                if 0 < quarter && x < quarter && y < quarter {
                    shift = baseShift
                }
            }
            if shift < 0 { shift = 0 }

            let index = y * size + x
            block[index] <<= shift
        }
    }
}
