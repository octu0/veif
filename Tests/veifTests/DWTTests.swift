import XCTest
@testable import veif

final class DWTTests: XCTestCase {
    
    func testDWTReversibility() {
        // LeGall 5/3 DWT is integer reversible.
        // We test with random data.
        
        let size = 16
        var original = [Int16](repeating: 0, count: size * size)
        
        // Random input (simulating pixel values or residuals)
        for i in 0..<original.count {
            original[i] = Int16.random(in: -255...255)
        }
        
        // Copy for processing
        var buffer = original
        
        // Forward DWT
        buffer.withUnsafeMutableBufferPointer { bp in
            if let ptr = bp.baseAddress {
                dwtBlock(data: ptr, size: size)
            }
        }
        
        // Inverse DWT
        buffer.withUnsafeMutableBufferPointer { bp in
            if let ptr = bp.baseAddress {
                invDwtBlock(data: ptr, size: size)
            }
        }
        
        // Check equality
        for i in 0..<original.count {
            XCTAssertEqual(buffer[i], original[i], "Mismatch at index \(i): got \(buffer[i]), want \(original[i])")
        }
    }
    
    func testDWT2LevelReversibility() {
        let size = 32
        var original = [Int16](repeating: 0, count: size * size)
        
        for i in 0..<original.count {
            original[i] = Int16.random(in: -255...255)
        }
        
        var buffer = original
        
        // Forward 2-Level
        buffer.withUnsafeMutableBufferPointer { bp in
            if let ptr = bp.baseAddress {
                dwtBlock2Level(data: ptr, size: size)
            }
        }
        
        // Inverse 2-Level
        buffer.withUnsafeMutableBufferPointer { bp in
            if let ptr = bp.baseAddress {
                invDwtBlock2Level(data: ptr, size: size)
            }
        }
        
        for i in 0..<original.count {
            XCTAssertEqual(buffer[i], original[i], "Mismatch at index \(i): got \(buffer[i]), want \(original[i])")
        }
    }
}
