
import XCTest
@testable import veif

final class HeaderTests: XCTestCase {
    
    func testDecodeBaseInvalidHeader() async throws {
        // 'VEIF' incorrect
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00]) 
        
        do {
            _ = try await decodeBase(r: data, size: 8, layer: 0)
            XCTFail("Should have thrown error")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "DecodeError")
            XCTAssertEqual(nsError.code, 4) // Invalid Header
        }
    }
    
    func testDecodeBaseInvalidLayer() async throws {
        // 'VEIF' correct, layer incorrect (expect 0, got 1)
        let data = Data([0x56, 0x45, 0x49, 0x46, 0x01])
        
        do {
            _ = try await decodeBase(r: data, size: 8, layer: 0)
            XCTFail("Should have thrown error")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "DecodeError")
            XCTAssertEqual(nsError.code, 5) // Invalid Layer Number
        }
    }

    func testDecodeLayerInvalidHeader() async throws {
        // 'VEIF' incorrect
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x01])
        let dummyPrev = Image16(width: 8, height: 8)
        
        do {
            _ = try await decodeLayer(r: data, prev: dummyPrev, size: 16, layer: 1)
            XCTFail("Should have thrown error")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "DecodeError")
            XCTAssertEqual(nsError.code, 4) // Invalid Header
        }
    }

    func testDecodeLayerInvalidLayer() async throws {
        // 'VEIF' correct, layer incorrect (expect 1, got 2)
        let data = Data([0x56, 0x45, 0x49, 0x46, 0x02])
        let dummyPrev = Image16(width: 8, height: 8)
        
        do {
            _ = try await decodeLayer(r: data, prev: dummyPrev, size: 16, layer: 1)
            XCTFail("Should have thrown error")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "DecodeError")
            XCTAssertEqual(nsError.code, 5) // Invalid Layer Number
        }
    }
}
