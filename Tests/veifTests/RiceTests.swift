import XCTest
@testable import veif

final class RiceTests: XCTestCase {
    
    func testBitWriterReader() throws {
        let writer = BitWriter()
        
        let bitsToWrite: [UInt8] = [1, 0, 1, 1, 0]
        for b in bitsToWrite {
            writer.writeBit(b)
        }
        
        let val16: UInt16 = 0xAAAA
        writer.writeBits(val: val16, n: 16)
        
        writer.flush()
        let data = writer.data
        
        let reader = BitReader(data: data)
        for (i, want) in bitsToWrite.enumerated() {
            let got = try reader.readBit()
            XCTAssertEqual(got, want, "Index \(i): got \(got), want \(want)")
        }
        
        let gotVal16 = try reader.readBits(n: 16)
        XCTAssertEqual(UInt16(gotVal16), val16, "ReadBits: got \(String(format: "%x", gotVal16)), want \(String(format: "%x", val16))")
    }
    
    func testRiceRoundTripMinMax() throws {
        struct Case {
            let val: UInt16
            let k: Int
        }
        
        let cases: [Case] = [
            Case(val: 0, k: 0),
            Case(val: 0, k: 5),
            Case(val: 1, k: 0),
            Case(val: 10, k: 0),
            Case(val: 255, k: 8),
            Case(val: 1024, k: 10),
            Case(val: 65535, k: 15),
        ]
        
        let writer = BitWriter()
        let rw = RiceWriter<UInt16>(bw: writer)
        
        for c in cases {
            rw.write(val: c.val, k: UInt8(c.k))
        }
        writer.flush()
        let data = writer.data
        
        let reader = BitReader(data: data)
        let rr = RiceReader<UInt16>(br: reader)
        
        for (i, c) in cases.enumerated() {
            let got = try rr.readRice(k: UInt8(c.k))
            XCTAssertEqual(got, c.val, "Case \(i): got \(got), want \(c.val) (k=\(c.k))")
        }
    }
    
    func testRiceRandom() throws {
        let numTests = 10000
        struct Input {
            let val: UInt16
            let k: Int
        }
        var inputs: [Input] = []
        
        let writer = BitWriter()
        let rw = RiceWriter<UInt16>(bw: writer)
        
        for _ in 0..<numTests {
            let k = Int.random(in: 0..<16)
            let val = UInt16.random(in: 0...UInt16.max)
            inputs.append(Input(val: val, k: k))
            rw.write(val: val, k: UInt8(k))
        }
        writer.flush()
        let data = writer.data
        
        let reader = BitReader(data: data)
        let rr = RiceReader<UInt16>(br: reader)
        
        for (i, inp) in inputs.enumerated() {
            let got = try rr.readRice(k: UInt8(inp.k))
            XCTAssertEqual(got, inp.val, "Random test \(i): got \(got), want \(inp.val) (k=\(inp.k))")
        }
    }
    
    func testRiceK0() throws {
        let writer = BitWriter()
        let rw = RiceWriter<UInt16>(bw: writer)
        
        rw.write(val: 3, k: 0)
        rw.write(val: 1, k: 0)
        writer.flush()
        let data = writer.data
        
        XCTAssertEqual(data.count, 1, "Expected 1 byte, got \(data.count)")
        let expected: UInt8 = 0xE8 // 11101000
        if let byte = data.first {
            XCTAssertEqual(byte, expected, "Byte content mismatch: got \(String(format: "%02x", byte)), want \(String(format: "%02x", expected))")
        }
    }
}
