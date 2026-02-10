import XCTest
@testable import veif

final class QuantTests: XCTestCase {
    
    func testQuantDequantRoundTrip() {
        let size = 16
        let scale = 0
        var original = [Int16](repeating: 0, count: size * size)
        
        // Fill with some values
        for i in 0..<original.count {
            original[i] = Int16(i % 256)
        }
        
        var buffer = original
        
        // Quantize
        buffer.withUnsafeMutableBufferPointer { bp in
            if let ptr = bp.baseAddress {
                quantizeBlock(block: ptr, size: size, scale: scale)
            }
        }
        
        // Dequantize
        buffer.withUnsafeMutableBufferPointer { bp in
            dequantizeBlock(block: bp, size: size, scale: scale)
        }
        
        // Verify
        for y in 0..<size {
            for x in 0..<size {
                let index = y * size + x
                let org = Int(original[index])
                let res = Int(buffer[index])
                
                // Calculate expected shift based on logic in Quant.swift
                var shift = scale + 5
                let half = size / 2
                let quarter = size < 16 ? 0 : size / 4
                
                if x < half && y < half {
                    shift = scale + 2
                    if 0 < quarter && x < quarter && y < quarter {
                        shift = scale
                    }
                }
                
                // If shift is 0, exact match
                if shift == 0 {
                    XCTAssertEqual(res, org, "Mismatch at \(x),\(y) with shift 0")
                } else {
                    // Check if result is close (quantization error)
                    // The error should be within +/- (1 << shift) roughly
                    let diff = abs(res - org)
                    let tolerance = (1 << shift)
                    XCTAssertLessThan(diff, tolerance, "Difference \(diff) too large at \(x),\(y) (shift \(shift), org \(org), res \(res))")
                    
                    // Also verify the exact logic:
                    // Q: v = (org + (1<<(s-1))) >> s
                    // DQ: res = v << s
                    let offset = 1 << (shift - 1)
                    let qVal = (org + offset) >> shift
                    let expectedRes = qVal << shift
                    XCTAssertEqual(res, expectedRes, "Math mismatch at \(x),\(y)")
                }
            }
        }
    }
}
