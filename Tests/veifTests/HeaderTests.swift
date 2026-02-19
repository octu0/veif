
import Testing
@testable import veif

@Suite("Header Validation Tests")
struct HeaderTests {
    
    @Test("decodeBase: invalid header")
    func testDecodeBaseInvalidHeader() async {
        // 'VEIF' incorrect
        let data: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00]
        
        do {
            _ = try await decodeBase(r: data, layer: 0, size: 8)
            Issue.record("Should have thrown error")
        } catch let error as DecodeError {
            #expect(error == .invalidHeader)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("decodeBase: invalid layer number")
    func testDecodeBaseInvalidLayer() async {
        // 'VEIF' correct, layer incorrect (expect 0, got 1)
        let data: [UInt8] = [0x56, 0x45, 0x49, 0x46, 0x01]
        
        do {
            _ = try await decodeBase(r: data, layer: 0, size: 8)
            Issue.record("Should have thrown error")
        } catch let error as DecodeError {
            #expect(error == .invalidLayerNumber)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("decodeLayer: invalid header")
    func testDecodeLayerInvalidHeader() async {
        // 'VEIF' incorrect
        let data: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x01]
        let dummyPrev = Image16(width: 8, height: 8)
        
        do {
            _ = try await decodeLayer(r: data, layer: 1, prev: dummyPrev, size: 16)
            Issue.record("Should have thrown error")
        } catch let error as DecodeError {
            #expect(error == .invalidHeader)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("decodeLayer: invalid layer number")
    func testDecodeLayerInvalidLayer() async {
        // 'VEIF' correct, layer incorrect (expect 1, got 2)
        let data: [UInt8] = [0x56, 0x45, 0x49, 0x46, 0x02]
        let dummyPrev = Image16(width: 8, height: 8)
        
        do {
            _ = try await decodeLayer(r: data, layer: 1, prev: dummyPrev, size: 16)
            Issue.record("Should have thrown error")
        } catch let error as DecodeError {
            #expect(error == .invalidLayerNumber)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
