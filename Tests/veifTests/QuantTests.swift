import Testing
@testable import veif

// MARK: - Quantize Tests

private func referenceQuantize(_ data: inout Block2D, size: Int, q: Quantizer) {
    let total = (size * size)
    let mul = q.mul
    let shift = Int32(q.shift)
    for i in 0..<total {
        let val = Int32(data.data[i])
        let absVal = abs(val)
        let qVal = (absVal &* mul) &>> shift
        data.data[i] = Int16(val < 0 ? -1 * qVal : qVal)
    }
}

private func referenceQuantizeSignedMapping(_ data: inout Block2D, size: Int, q: Quantizer) {
    let total = (size * size)
    let mul = q.mul
    let shift = Int32(q.shift)
    for i in 0..<total {
        let val = Int32(data.data[i])
        let absVal = abs(val)
        let qVal = (absVal &* mul) &>> shift
        let v = Int16(val < 0 ? -1 * qVal : qVal)
        
        let u = UInt16(bitPattern: (v &<< 1) ^ (v >> 15))
        data.data[i] = Int16(bitPattern: u)
    }
}

private func referenceDequantize(_ data: inout Block2D, size: Int, q: Quantizer) {
    let total = (size * size)
    let step = Int32(q.step)
    for i in 0..<total {
        let val = Int32(data.data[i])
        data.data[i] = Int16(clamping: (val &* step))
    }
}

private func referenceDequantizeSignedMapping(_ data: inout Block2D, size: Int, q: Quantizer) {
    let total = (size * size)
    let step = Int32(q.step)
    for i in 0..<total {
        let uVal = UInt16(bitPattern: data.data[i])
        let decodedUInt = (uVal >> 1) ^ (0 &- (uVal & 1))
        let decoded = Int16(bitPattern: decodedUInt)
        data.data[i] = Int16(clamping: Int32(decoded) &* step)
    }
}

private func makeTestBlock(size: Int, seed: Int16) -> Block2D {
    let block = Block2D(width: size, height: size)
    for y in 0..<size {
        for x in 0..<size {
            let val = Int16(((y * size) + x)) &- seed
            block[y, x] = val
        }
    }
    return block
}

// MARK: - quantizeLow / quantizeMid / quantizeHigh Tests

@Suite("Quantization SIMD Tests")
struct QuantizeSIMDTests {

    @Test("quantizeLow: 4x4 block", arguments: [4, 8, 16])
    func quantizeLow4x4(baseStep: Int) {
        let size = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: 8)
        var expected = actual

        quantizeLow(&actual, qt: qt)
        referenceQuantize(&expected, size: size, q: qt.qLow)

        #expect(actual.data == expected.data, "data mismatch")
    }

    @Test("quantizeLow: 8x8 block", arguments: [4, 8, 16])
    func quantizeLow8x8(baseStep: Int) {
        let size = 8
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: 32)
        var expected = actual

        quantizeLow(&actual, qt: qt)
        referenceQuantize(&expected, size: size, q: qt.qLow)

        #expect(actual.data == expected.data, "data mismatch")
    }

    @Test("quantizeLow: 16x16 block", arguments: [4, 8, 16])
    func quantizeLow16x16(baseStep: Int) {
        let size = 16
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: 128)
        var expected = actual

        quantizeLow(&actual, qt: qt)
        referenceQuantize(&expected, size: size, q: qt.qLow)

        #expect(actual.data == expected.data, "data mismatch")
    }

    @Test("quantizeLow: 32x32 block", arguments: [4, 8, 16])
    func quantizeLow32x32(baseStep: Int) {
        let size = 32
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: 512)
        var expected = actual

        quantizeLow(&actual, qt: qt)
        referenceQuantize(&expected, size: size, q: qt.qLow)

        #expect(actual.data == expected.data, "data mismatch")
    }

    @Test("quantizeMid: All sizes", arguments: [4, 8, 16, 32])
    func quantizeMidAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size))
        var expected = actual

        quantizeMid(&actual, qt: qt)
        referenceQuantize(&expected, size: size, q: qt.qMid)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("quantizeHigh: All sizes", arguments: [4, 8, 16, 32])
    func quantizeHighAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size))
        var expected = actual

        quantizeHigh(&actual, qt: qt)
        referenceQuantize(&expected, size: size, q: qt.qHigh)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("quantizeMid (SignedMapping): All sizes", arguments: [4, 8, 16, 32])
    func quantizeMidSignedMappingAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size))
        var expected = actual

        quantizeMidSignedMapping(&actual, qt: qt)
        referenceQuantizeSignedMapping(&expected, size: size, q: qt.qMid)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("quantizeHigh (SignedMapping): All sizes", arguments: [4, 8, 16, 32])
    func quantizeHighSignedMappingAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size))
        var expected = actual

        quantizeHighSignedMapping(&actual, qt: qt)
        referenceQuantizeSignedMapping(&expected, size: size, q: qt.qHigh)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }
}

// MARK: - dequantizeLow / dequantizeMid / dequantizeHigh Tests

@Suite("Dequantization SIMD Tests")
struct DequantizeSIMDTests {

    @Test("dequantizeLow: All sizes", arguments: [4, 8, 16, 32])
    func dequantizeLowAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeLow(&actual, qt: qt)
        referenceDequantize(&expected, size: size, q: qt.qLow)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("dequantizeMid: All sizes", arguments: [4, 8, 16, 32])
    func dequantizeMidAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeMid(&actual, qt: qt)
        referenceDequantize(&expected, size: size, q: qt.qMid)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("dequantizeHigh: All sizes", arguments: [4, 8, 16, 32])
    func dequantizeHighAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeHigh(&actual, qt: qt)
        referenceDequantize(&expected, size: size, q: qt.qHigh)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("dequantizeMid (SignedMapping): All sizes", arguments: [4, 8, 16, 32])
    func dequantizeMidSignedMappingAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeMidSignedMapping(&actual, qt: qt)
        referenceDequantizeSignedMapping(&expected, size: size, q: qt.qMid)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }

    @Test("dequantizeHigh (SignedMapping): All sizes", arguments: [4, 8, 16, 32])
    func dequantizeHighSignedMappingAllSizes(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeHighSignedMapping(&actual, qt: qt)
        referenceDequantizeSignedMapping(&expected, size: size, q: qt.qHigh)

        #expect(actual.data == expected.data, "size=\(size) data mismatch")
    }
}

// MARK: - Roundtrip Tests

@Suite("Quantize/Dequantize Roundtrip Tests")
struct QuantRoundtripTests {

    @Test("quantize->dequantize Roundtrip: All sizes", arguments: [4, 8, 16, 32])
    func roundtrip(size: Int) {
        let baseStep = 4
        let qt = QuantizationTable(baseStep: baseStep)

        var block = makeTestBlock(size: size, seed: Int16(size))
        let original = block

        // quantize (Low)
        quantizeLow(&block, qt: qt)
        // dequantize (Low)
        dequantizeLow(&block, qt: qt)

        // Confirm it's within the quantization error range after roundtrip
        let maxError = Int16(qt.qLow.step)
        let total = (size * size)
        for i in 0..<total {
            let diff = abs(Int32(block.data[i]) - Int32(original.data[i]))
            #expect(diff <= Int32(maxError), "size=\(size) [\(i)] error \(diff) exceeded max allowed \(maxError)")
        }
    }
}
