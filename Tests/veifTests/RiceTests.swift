import Testing
import Foundation
@testable import veif

@Suite("Rice Coding Tests")
struct RiceTests {

    @Test("ZigZag Conversion Roundtrip")
    func zigzagRoundtrip() {
        let values: [Int16] = [0, 1, -1, 2, -2, 100, -100, Int16.max, Int16.min]
        for v in values {
            let u = toUint16(v)
            let back = toInt16(u)
            #expect(v == back, "Value \(v) failed zigzag roundtrip")
        }
    }

    @Test("BitWriter / BitReader Roundtrip")
    func bitWriterReaderRoundtrip() throws {
        let data = NSMutableData()
        let bw = BitWriter(data: data)
        
        bw.writeBit(1)
        bw.writeBit(0)
        bw.writeBits(val: 0x05, n: 3) // 101
        bw.writeBit(1)
        bw.flush()
        
        let br = BitReader(data: data as Data)
        #expect(try br.readBit() == 1)
        #expect(try br.readBit() == 0)
        #expect(try br.readBits(n: 3) == 0x05)
        #expect(try br.readBit() == 1)
    }

    @Test("Rice Coding: No Zeros")
    func riceNoZeros() throws {
        let data = NSMutableData()
        let bw = BitWriter(data: data)
        let rw = RiceWriter(bw: bw)
        
        let values: [UInt16] = [1, 2, 3, 10, 20, 100]
        let k: UInt8 = 2
        
        for v in values {
            rw.write(val: v, k: k)
        }
        rw.flush()
        
        let br = BitReader(data: data as Data)
        let rr = RiceReader(br: br)
        
        for v in values {
            let decoded = try rr.read(k: k)
            #expect(decoded == v)
        }
    }

    @Test("Rice Coding: With Zero-runs")
    func riceWithZeroRuns() throws {
        let data = NSMutableData()
        let bw = BitWriter(data: data)
        let rw = RiceWriter(bw: bw)
        
        // 0 が連続するパターン
        // [1, 0, 0, 0, 2, 0 (64 times), 3]
        var input: [UInt16] = [1, 0, 0, 0, 2]
        for _ in 0..<64 {
            input.append(0)
        }
        input.append(3)
        
        let k: UInt8 = 3
        for v in input {
            rw.write(val: v, k: k)
        }
        rw.flush()
        
        let br = BitReader(data: data as Data)
        let rr = RiceReader(br: br)
        
        for (i, v) in input.enumerated() {
            let decoded = try rr.read(k: k)
            #expect(decoded == v, "Failed at index \(i)")
        }
    }

    @Test("Rice Coding: Long Zero-run (Edge case)")
    func riceLongZeroRun() throws {
        let data = NSMutableData()
        let bw = BitWriter(data: data)
        let rw = RiceWriter(bw: bw)
        
        // maxVal(64) を超える 0 の連続
        let zeroCount = 150
        var input = [UInt16](repeating: 0, count: zeroCount)
        input.append(1) // 最後に非ゼロ
        
        let k: UInt8 = 2
        for v in input {
            rw.write(val: v, k: k)
        }
        rw.flush()
        
        let br = BitReader(data: data as Data)
        let rr = RiceReader(br: br)
        
        for (i, v) in input.enumerated() {
            let decoded = try rr.read(k: k)
            #expect(decoded == v, "Failed at index \(i)")
        }
    }
}
