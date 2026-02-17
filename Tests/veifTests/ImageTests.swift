import XCTest
@testable import veif

final class ImageTests: XCTestCase {
    
    func testUpdateY() {
        var image = Image16(width: 8, height: 8)
        var block = Block2D(width: 4, height: 4)
        for h in 0..<4 {
            for w in 0..<4 {
                block[h, w] = Int16(h * 4 + w + 1)
            }
        }
        
        // Normal update
        image.updateY(data: block, startX: 0, startY: 0, size: 4)
        
        for h in 0..<4 {
            for w in 0..<4 {
                XCTAssertEqual(image.y[h][w], Int16(h * 4 + w + 1))
            }
        }
        
        // Boundary update (clipping)
        image.updateY(data: block, startX: 6, startY: 6, size: 4)
        // Should update (6,6), (6,7), (7,6), (7,7)
        // Block data indices:
        // h=0, w=0 -> 1 -> img[6][6]
        // h=0, w=1 -> 2 -> img[6][7]
        // h=1, w=0 -> 5 -> img[7][6]
        // h=1, w=1 -> 6 -> img[7][7]
        
        XCTAssertEqual(image.y[6][6], 1)
        XCTAssertEqual(image.y[6][7], 2)
        XCTAssertEqual(image.y[7][6], 5)
        XCTAssertEqual(image.y[7][7], 6)
        
        // Ensure no overflow / crash for out of bounds
        image.updateY(data: block, startX: 8, startY: 8, size: 4) // Completely out
        image.updateY(data: block, startX: -10, startY: -10, size: 4) // Negative out (though size is usually positive, logic handles startX/Y relative to loops)
    }

    func testUpdateCb() {
        var image = Image16(width: 8, height: 8)
        // Cb size is 4x4
        var block = Block2D(width: 2, height: 2)
        block[0, 0] = 10
        block[0, 1] = 20
        block[1, 0] = 30
        block[1, 1] = 40
        
        // Normal update
        image.updateCb(data: block, startX: 0, startY: 0, size: 2)
        XCTAssertEqual(image.cb[0][0], 10)
        XCTAssertEqual(image.cb[0][1], 20)
        XCTAssertEqual(image.cb[1][0], 30)
        XCTAssertEqual(image.cb[1][1], 40)
        
        // Boundary update (clipping)
        // Cb width is 4. startX=3. size=2.
        // w=0 -> x=3. valid.
        // w=1 -> x=4. invalid (width is 4, indices 0..3).
        image.updateCb(data: block, startX: 3, startY: 0, size: 2)
        XCTAssertEqual(image.cb[0][3], 10)
        // cb[0][4] should not be touched / exist (out of bounds)
        
        // Check verify checking logic
        // halfWidth = 4.
        // endX = min(3 + 2, 4) = 4.
        // startX = 3.
        // loopW = 4 - 3 = 1.
        // Correct.
        
        // Boundary Height
        // Cb height 4. startY=3. size=2.
        image.updateCb(data: block, startX: 0, startY: 3, size: 2)
        XCTAssertEqual(image.cb[3][0], 10)
    }

    func testUpdateCr() {
        var image = Image16(width: 8, height: 8)
        var block = Block2D(width: 2, height: 2)
        block[0, 0] = 99
        
        image.updateCr(data: block, startX: 0, startY: 0, size: 2)
        XCTAssertEqual(image.cr[0][0], 99)
    }

    func testToYCbCr() {
        var image = Image16(width: 4, height: 4)
        
        // Fill Y
        image.y[0][0] = 100
        image.y[0][1] = 300 // Should clamp to 255
        image.y[0][2] = -50 // Should clamp to 0
        image.y[0][3] = 128
        
        // Fill Cb/Cr (size 2x2)
        image.cb[0][0] = 50
        image.cb[0][1] = 200
        
        image.cr[0][0] = -10
        image.cr[0][1] = 260
        
        let ycbcr = image.toYCbCr()
        
        XCTAssertEqual(ycbcr.width, 4)
        XCTAssertEqual(ycbcr.height, 4)
        
        // Check Y
        XCTAssertEqual(ycbcr.yPlane[ycbcr.yOffset(0, 0)], 100)
        XCTAssertEqual(ycbcr.yPlane[ycbcr.yOffset(1, 0)], 255)
        XCTAssertEqual(ycbcr.yPlane[ycbcr.yOffset(2, 0)], 0)
        XCTAssertEqual(ycbcr.yPlane[ycbcr.yOffset(3, 0)], 128)
        
        // Check Cb
        // 4:2:0 subsampling by default in Image16? 
        // Image16 stores Cb/Cr as size/2. YCbCrImage default is 4:2:0.
        // Cb size in YCbCrImage for 4x4 image is 2x2.
        // indices: (0,0), (1,0), (0,1), (1,1)
        
        XCTAssertEqual(ycbcr.cbPlane[ycbcr.cOffset(0, 0)], 50)
        XCTAssertEqual(ycbcr.cbPlane[ycbcr.cOffset(1, 0)], 200)
        
        XCTAssertEqual(ycbcr.crPlane[ycbcr.cOffset(1, 0)], 255)
    }

    func testRowY() {
        let width = 8
        let height = 8
        var img = YCbCrImage(width: width, height: height)
        
        // Fill Y with known pattern
        for y in 0..<height {
            for x in 0..<width {
                let off = img.yOffset(x, y)
                img.yPlane[off] = UInt8(y * 10 + x)
            }
        }
        
        let reader = ImageReader(img: img)
        
        // Test rowY normal (x=0, y=0, size=8)
        let row0 = reader.rowY(x: 0, y: 0, size: 8)
        XCTAssertEqual(row0.count, 8)
        XCTAssertEqual(row0[0], 0)
        XCTAssertEqual(row0[7], 7)
               
        // Test rowY offset (x=2, y=2, size=4)
        let row2 = reader.rowY(x: 2, y: 2, size: 4)
        XCTAssertEqual(row2[0], 22) // 2*10+2
        XCTAssertEqual(row2[3], 25) // 2*10+5
        
        // Test rowY boundary
        // x=6, size=4. Width 8.
        // i=0 -> x=6 -> val=6
        // i=1 -> x=7 -> val=7
        // i=2 -> x=8 -> boundaryRepeat -> x=7 -> val=7
        // i=3 -> x=9 -> boundaryRepeat -> x=6 -> val=6
        let rowBoundary = reader.rowY(x: 6, y: 0, size: 4)
        XCTAssertEqual(rowBoundary[0], 6)
        XCTAssertEqual(rowBoundary[1], 7)
        XCTAssertEqual(rowBoundary[2], 7)
        XCTAssertEqual(rowBoundary[3], 6)
    }
}
