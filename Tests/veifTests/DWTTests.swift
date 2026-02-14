import Testing
@testable import veif

@Suite("DWT SIMD Tests")
struct DWTTests {

    /// テストデータ生成
    private func makeTestData(size: Int, seed: Int16) -> [Int16] {
        var data = [Int16](repeating: 0, count: size)
        for i in 0..<size {
            data[i] = Int16(i) &- seed
        }
        return data
    }

    @Test("lift53 / invLift53 Roundtrip: size=8 (SIMD4)", arguments: [0, 10, 100])
    func roundtripSize8(seed: Int) {
        let size = 8
        var data = makeTestData(size: size, seed: Int16(seed))
        let original = data
        
        data.withUnsafeMutableBufferPointer { ptr in
            lift53(ptr, count: size, stride: 1)
            invLift53(ptr, count: size, stride: 1)
        }
        
        #expect(data == original, "Seed: \(seed) - データが元に戻りません")
    }

    @Test("lift53 / invLift53 Roundtrip: size=16 (SIMD8)", arguments: [0, 10, 100])
    func roundtripSize16(seed: Int) {
        let size = 16
        var data = makeTestData(size: size, seed: Int16(seed))
        let original = data
        
        data.withUnsafeMutableBufferPointer { ptr in
            lift53(ptr, count: size, stride: 1)
            invLift53(ptr, count: size, stride: 1)
        }
        
        #expect(data == original, "Seed: \(seed) - データが元に戻りません")
    }

    @Test("lift53 / invLift53 Roundtrip: size=32 (SIMD16)", arguments: [0, 10, 100])
    func roundtripSize32(seed: Int) {
        let size = 32
        var data = makeTestData(size: size, seed: Int16(seed))
        let original = data
        
        data.withUnsafeMutableBufferPointer { ptr in
            lift53(ptr, count: size, stride: 1)
            invLift53(ptr, count: size, stride: 1)
        }
        
        #expect(data == original, "Seed: \(seed) - データが元に戻りません")
    }
    
    @Test("lift53 / invLift53 Roundtrip: size=4 (Scalar Fallback)", arguments: [0, 10])
    func roundtripSize4(seed: Int) {
        let size = 4
        var data = makeTestData(size: size, seed: Int16(seed))
        let original = data
        
        data.withUnsafeMutableBufferPointer { ptr in
            lift53(ptr, count: size, stride: 1)
            invLift53(ptr, count: size, stride: 1)
        }
        
        #expect(data == original, "Seed: \(seed) - データが元に戻りません")
    }
    
    @Test("dwt2d / invDwt2d Roundtrip: size=32", arguments: [0])
    func dwt2dRoundtrip(seed: Int) {
        let size = 32
        var block = Block2D(width: size, height: size)
        for y in 0..<size {
             for x in 0..<size {
                 block[y, x] = Int16((y * size + x))
             }
        }
        let original = block
        
        let sub = dwt2d(&block, size: size)
        let restored = invDwt2d(sub)
        
        #expect(restored.data == original.data, "2D DWT ラウンドトリップ失敗")
    }
}
