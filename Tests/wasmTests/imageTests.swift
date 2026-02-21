import Testing
@testable import wasm

@Suite("wasm/Image Tests")
struct ImageTests {
    
    @Test("rgbaToYCbCr Roundtrip: size=4")
    func rgbaToYCbCrRoundtrip() {
        let width = 4
        let height = 4
        var rgbaData = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            rgbaData[i * 4 + 0] = 100 // R
            rgbaData[i * 4 + 1] = 150 // G
            rgbaData[i * 4 + 2] = 200 // B
        }
        
        let ycbcr = rgbaToYCbCr(data: rgbaData, width: width, height: height)
        #expect(ycbcr.width == width)
        #expect(ycbcr.height == height)
        
        let yVal = (19595 * 100 + 38470 * 150 + 7471 * 200 + (1 << 15)) >> 16
        let cbVal = ((-11059 * 100 - 21709 * 150 + 32768 * 200 + (1 << 15)) >> 16) + 128
        let crVal = ((32768 * 100 - 27439 * 150 - 5329 * 200 + (1 << 15)) >> 16) + 128
        
        for y in 0..<height {
            for x in 0..<width {
                let yIdx = ycbcr.yOffset(x, y)
                let cOff = ycbcr.cOffset(x, y)
                
                #expect(ycbcr.yPlane[yIdx] == UInt8(clamping: yVal))
                #expect(ycbcr.cbPlane[cOff] == UInt8(clamping: cbVal))
                #expect(ycbcr.crPlane[cOff] == UInt8(clamping: crVal))
            }
        }
    }
}