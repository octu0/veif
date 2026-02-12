import Testing
@testable import veif

// MARK: - Quantize Tests

/// スカラー版の quantize を再実装（テスト用参照実装）
private func referenceQuantize(_ data: inout Block2D, size: Int, scale: Int) {
    let total = (size * size)
    for i in 0..<total {
        let v = Int32(data.data[i])
        let off = Int32(1 << (scale - 1))
        if 0 <= v {
            data.data[i] = Int16((v + off) >> scale)
        } else {
            data.data[i] = Int16(-1 * ((-1 * v + off) >> scale))
        }
    }
}

/// スカラー版の dequantize を再実装（テスト用参照実装）
private func referenceDequantize(_ data: inout Block2D, size: Int, scale: Int) {
    let total = (size * size)
    for i in 0..<total {
        data.data[i] = (data.data[i] &<< scale)
    }
}

/// テスト用のブロックデータを生成する
/// 正・負・ゼロを含むパターンを生成
private func makeTestBlock(size: Int, seed: Int16) -> Block2D {
    var block = Block2D(width: size, height: size)
    for y in 0..<size {
        for x in 0..<size {
            let val = Int16(((y * size) + x)) &- seed
            block[y, x] = val
        }
    }
    return block
}

// MARK: - quantizeLow / quantizeMid / quantizeHigh のテスト

@Suite("Quantization SIMD Tests")
struct QuantizeSIMDTests {

    @Test("quantizeLow: 4x4 ブロック", arguments: [1, 2, 3])
    func quantizeLow4x4(scale: Int) {
        let size = 4
        var actual = makeTestBlock(size: size, seed: 8)
        var expected = actual

        quantizeLow(&actual, size: size, scale: scale)
        referenceQuantize(&expected, size: size, scale: (scale + 2))

        #expect(actual.data == expected.data, "データが一致しません")
    }

    @Test("quantizeLow: 8x8 ブロック", arguments: [1, 2, 3])
    func quantizeLow8x8(scale: Int) {
        let size = 8
        var actual = makeTestBlock(size: size, seed: 32)
        var expected = actual

        quantizeLow(&actual, size: size, scale: scale)
        referenceQuantize(&expected, size: size, scale: (scale + 2))

        #expect(actual.data == expected.data, "データが一致しません")
    }

    @Test("quantizeLow: 16x16 ブロック", arguments: [1, 2, 3])
    func quantizeLow16x16(scale: Int) {
        let size = 16
        var actual = makeTestBlock(size: size, seed: 128)
        var expected = actual

        quantizeLow(&actual, size: size, scale: scale)
        referenceQuantize(&expected, size: size, scale: (scale + 2))

        #expect(actual.data == expected.data, "データが一致しません")
    }

    @Test("quantizeLow: 32x32 ブロック", arguments: [1, 2, 3])
    func quantizeLow32x32(scale: Int) {
        let size = 32
        var actual = makeTestBlock(size: size, seed: 512)
        var expected = actual

        quantizeLow(&actual, size: size, scale: scale)
        referenceQuantize(&expected, size: size, scale: (scale + 2))

        #expect(actual.data == expected.data, "データが一致しません")
    }

    @Test("quantizeMid: 全サイズ", arguments: [4, 8, 16, 32])
    func quantizeMidAllSizes(size: Int) {
        let scale = 2
        var actual = makeTestBlock(size: size, seed: Int16(size))
        var expected = actual

        quantizeMid(&actual, size: size, scale: scale)
        referenceQuantize(&expected, size: size, scale: (scale + 3))

        #expect(actual.data == expected.data, "size=\(size) データが一致しません")
    }

    @Test("quantizeHigh: 全サイズ", arguments: [4, 8, 16, 32])
    func quantizeHighAllSizes(size: Int) {
        let scale = 2
        var actual = makeTestBlock(size: size, seed: Int16(size))
        var expected = actual

        quantizeHigh(&actual, size: size, scale: scale)
        referenceQuantize(&expected, size: size, scale: (scale + 5))

        #expect(actual.data == expected.data, "size=\(size) データが一致しません")
    }
}

// MARK: - dequantizeLow / dequantizeMid / dequantizeHigh のテスト

@Suite("Dequantization SIMD Tests")
struct DequantizeSIMDTests {

    @Test("dequantizeLow: 全サイズ", arguments: [4, 8, 16, 32])
    func dequantizeLowAllSizes(size: Int) {
        let scale = 2
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeLow(&actual, size: size, scale: scale)
        referenceDequantize(&expected, size: size, scale: (scale + 2))

        #expect(actual.data == expected.data, "size=\(size) データが一致しません")
    }

    @Test("dequantizeMid: 全サイズ", arguments: [4, 8, 16, 32])
    func dequantizeMidAllSizes(size: Int) {
        let scale = 2
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeMid(&actual, size: size, scale: scale)
        referenceDequantize(&expected, size: size, scale: (scale + 3))

        #expect(actual.data == expected.data, "size=\(size) データが一致しません")
    }

    @Test("dequantizeHigh: 全サイズ", arguments: [4, 8, 16, 32])
    func dequantizeHighAllSizes(size: Int) {
        let scale = 2
        var actual = makeTestBlock(size: size, seed: Int16(size / 2))
        var expected = actual

        dequantizeHigh(&actual, size: size, scale: scale)
        referenceDequantize(&expected, size: size, scale: (scale + 5))

        #expect(actual.data == expected.data, "size=\(size) データが一致しません")
    }
}

// MARK: - ラウンドトリップテスト

@Suite("Quantize/Dequantize Roundtrip Tests")
struct QuantRoundtripTests {

    @Test("quantize→dequantize ラウンドトリップ: 全サイズ", arguments: [4, 8, 16, 32])
    func roundtrip(size: Int) {
        let scale = 2

        var block = makeTestBlock(size: size, seed: Int16(size))
        let original = block

        // quantize (Low: scale + 2)
        quantizeLow(&block, size: size, scale: scale)
        // dequantize (Low: scale + 2)
        dequantizeLow(&block, size: size, scale: scale)

        // ラウンドトリップ後、量子化誤差の範囲内であることを確認
        let totalScale = (scale + 2)
        let maxError = Int16(1 << totalScale)
        let total = (size * size)
        for i in 0..<total {
            let diff = abs(Int32(block.data[i]) - Int32(original.data[i]))
            #expect(diff <= Int32(maxError), "size=\(size) [\(i)] 誤差 \(diff) が最大許容値 \(maxError) を超えました")
        }
    }
}
