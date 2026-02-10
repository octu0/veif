import XCTest
@testable import veif

final class EndToEndTests: XCTestCase {
    func testEncodeDecode() throws {
        let width = 64
        let height = 64
        let img = Image16(width: width, height: height)
        
        // Generate pattern
        for y in 0..<height {
            for x in 0..<width {
                img.yPlane[img.yOffset(x: x, y: y)] = Int16(x + y)
            }
        }
        for y in 0..<height/2 {
            for x in 0..<width/2 {
                img.cbPlane[img.cOffset(x: x, y: y)] = Int16(x * 2)
                img.crPlane[img.cOffset(x: x, y: y)] = Int16(y * 2)
            }
        }
        
        let original = img.copy()
        
        let (layer0, layer1, layer2) = encode(img: img, maxbitrate: 100000)
        
        XCTAssertFalse(layer0.isEmpty, "Layer0 should not be empty")
        
        // Decode
        let layers = [layer0, layer1, layer2]
        let decoded = try decode(layers: layers)
        
        // Verify Dimensions
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        
        // PSNR
        let (psnrY, psnrCb, psnrCr, _) = calcPSNR(img1: original, img2: decoded)
        print("PSNR Y: \(psnrY), Cb: \(psnrCb), Cr: \(psnrCr)")
        
        XCTAssertGreaterThan(psnrY, 30.0)
        XCTAssertGreaterThan(psnrCb, 30.0)
        XCTAssertGreaterThan(psnrCr, 30.0)
    }
}
