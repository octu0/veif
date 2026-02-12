import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Utilities

func boundaryRepeat(_ width: Int, _ height: Int, _ px: Int, _ py: Int) -> (Int, Int) {
    var x = px
    var y = py
    
    // Width boundary
    if width <= x {
        x = (width - 1 - (x - width)) // Reflection
        if x < 0 {
            x = 0 // Clamp
        }
    } else {
        if x < 0 {
            x = (-1 * x)
            if width <= x {
                x = (width - 1)
            }
        }
    }
    
    // Height boundary
    if height <= y {
        y = (height - 1 - (y - height))
        if y < 0 {
            y = 0
        }
    } else {
        if y < 0 {
            y = (-1 * y)
            if height <= y {
                y = (height - 1)
            }
        }
    }
    
    return (x, y)
}

func clampU8(_ v: Int16) -> UInt8 {
    if v < 0 {
        return 0
    }
    if 255 < v {
        return 255
    }
    return UInt8(v)
}

// MARK: - Image Structures

public enum YCbCrRatio {
    case ratio420
    case ratio444
}

public struct YCbCrImage {
    public var yPlane: [UInt8]
    public var cbPlane: [UInt8]
    public var crPlane: [UInt8]
    public let width: Int
    public let height: Int
    public let ratio: YCbCrRatio
    
    public var yStride: Int { width }
    public var cStride: Int {
        switch ratio {
        case .ratio420: return (width / 2)
        case .ratio444: return width
        }
    }
    
    public init(width: Int, height: Int, ratio: YCbCrRatio = .ratio420) {
        self.width = width
        self.height = height
        self.ratio = ratio
        self.yPlane = [UInt8](repeating: 0, count: (width * height))
        
        switch ratio {
        case .ratio420:
            let cSize = ((width / 2) * (height / 2))
            self.cbPlane = [UInt8](repeating: 0, count: cSize)
            self.crPlane = [UInt8](repeating: 0, count: cSize)
        case .ratio444:
            let cSize = (width * height)
             self.cbPlane = [UInt8](repeating: 0, count: cSize)
             self.crPlane = [UInt8](repeating: 0, count: cSize)
        }
    }
    
    public func yOffset(_ x: Int, _ y: Int) -> Int {
        return ((y * yStride) + x)
    }
    
    public func cOffset(_ x: Int, _ y: Int) -> Int {
        return ((y * cStride) + x)
    }
}

public struct ImageReader {
    public let img: YCbCrImage
    public let width: Int
    public let height: Int
    
    public init(img: YCbCrImage) {
        self.img = img
        self.width = img.width
        self.height = img.height
    }
    
    public func rowY(x: Int, y: Int, size: Int, prediction: Int16) -> [Int16] {
        var plane = [Int16](repeating: 0, count: size)
        for i in 0..<size {
            let (px, py) = boundaryRepeat(width, height, (x + i), y)
            let offset = img.yOffset(px, py)
            plane[i] = (Int16(img.yPlane[offset]) - prediction)
        }
        return plane
    }
    
    public func rowCb(x: Int, y: Int, size: Int, prediction: Int16) -> [Int16] {
        var plane = [Int16](repeating: 0, count: size)
        for i in 0..<size {
            let (rPx, rPy) = boundaryRepeat(width, height, ((x + i) * 2), (y * 2))
            
            var cPx = rPx
            var cPy = rPy
            if img.ratio == .ratio420 {
                // Downsample for chroma lookup if 4:2:0
                cPx = (rPx / 2)
                cPy = (rPy / 2)
            }
            // If 4:4:4, we use full res coordinates (rPx, rPy) directly equivalent to cPx,cPy in 4:4:4 buffer
            
            let offset = img.cOffset(cPx, cPy)
            plane[i] = (Int16(img.cbPlane[offset]) - prediction)
        }
        return plane
    }
    
    public func rowCr(x: Int, y: Int, size: Int, prediction: Int16) -> [Int16] {
        var plane = [Int16](repeating: 0, count: size)
        for i in 0..<size {
            let (rPx, rPy) = boundaryRepeat(width, height, ((x + i) * 2), (y * 2))
            
            var cPx = rPx
            var cPy = rPy
            if img.ratio == .ratio420 {
                cPx = (rPx / 2)
                cPy = (rPy / 2)
            }
            
            let offset = img.cOffset(cPx, cPy)
            plane[i] = (Int16(img.crPlane[offset]) - prediction)
        }
        return plane
    }
}

public class ImagePredictor {
    public var img: YCbCrImage
    public let width: Int
    public let height: Int
    
    public init(width: Int, height: Int) {
        self.img = YCbCrImage(width: width, height: height, ratio: .ratio420)
        self.width = width
        self.height = height
    }
    
    public func updateY(x: Int, y: Int, size: Int, plane: [Int16], prediction: Int16) {
        for i in 0..<size {
            if width <= (x + i) || height <= y {
                continue
            }
            let offset = img.yOffset((x + i), y)
            img.yPlane[offset] = clampU8(plane[i] + prediction)
        }
    }
    
    public func updateCb(x: Int, y: Int, size: Int, plane: [Int16], prediction: Int16) {
        for i in 0..<size {
            let px = ((x + i) * 2)
            let py = (y * 2)
            if width <= px || height <= py {
                continue
            }
            // COffset takes full res coords and downsamples
            let cPx = (px / 2)
            let cPy = (py / 2)
            let offset = img.cOffset(cPx, cPy)
            img.cbPlane[offset] = clampU8(plane[i] + prediction)
        }
    }
    
    public func updateCr(x: Int, y: Int, size: Int, plane: [Int16], prediction: Int16) {
        for i in 0..<size {
            let px = ((x + i) * 2)
            let py = (y * 2)
            if width <= px || height <= py {
                continue
            }
            let cPx = (px / 2)
            let cPy = (py / 2)
            let offset = img.cOffset(cPx, cPy)
            img.crPlane[offset] = clampU8(plane[i] + prediction)
        }
    }
    
    public func predictY(x: Int, y: Int, size: Int) -> Int16 {
        return predictDC(data: img.yPlane, stride: img.yStride, offset: img.yOffset(x, y), x: x, y: y, size: size)
    }
    
    public func predictCb(x: Int, y: Int, size: Int) -> Int16 {
        let cPx = x 
        let cPy = y 
        return predictDC(data: img.cbPlane, stride: img.cStride, offset: img.cOffset(cPx, cPy), x: x, y: y, size: size)
    }
    
    public func predictCr(x: Int, y: Int, size: Int) -> Int16 {
        let cPx = x
        let cPy = y
        return predictDC(data: img.crPlane, stride: img.cStride, offset: img.cOffset(cPx, cPy), x: x, y: y, size: size)
    }
    
    private func predictDC(data: [UInt8], stride: Int, offset: Int, x: Int, y: Int, size: Int) -> Int16 {
        var sum = 0
        var count = 0
        
        if 0 < y {
            let topStart = (offset - stride)
            for i in 0..<size {
                if (topStart + i) < data.count {
                    sum += Int(data[topStart + i])
                    count += 1
                }
            }
        }
        
        if 0 < x {
            let leftStart = (offset - 1)
            for i in 0..<size {
                let idx = (leftStart + (i * stride))
                if idx < data.count {
                    sum += Int(data[idx])
                    count += 1
                }
            }
        }
        
        if count == 0 {
            return 128
        }
        return Int16(sum / count)
    }
}

public struct Image16 {
    public var y: [[Int16]]
    public var cb: [[Int16]]
    public var cr: [[Int16]]
    public let width: Int
    public let height: Int
    
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.y = [[Int16]](repeating: [Int16](repeating: 0, count: width), count: height)
        self.cb = [[Int16]](repeating: [Int16](repeating: 0, count: (width / 2)), count: (height / 2))
        self.cr = [[Int16]](repeating: [Int16](repeating: 0, count: (width / 2)), count: (height / 2))
    }
    
    public func getY(x: Int, y: Int, size: Int) -> [[Int16]] {
        var plane = [[Int16]](repeating: [Int16](repeating: 0, count: size), count: size)
        for h in 0..<size {
            for w in 0..<size {
                let (px, py) = boundaryRepeat(width, height, (x + w), (y + h))
                plane[h][w] = self.y[py][px]
            }
        }
        return plane
    }
    
    public func getCb(x: Int, y: Int, size: Int) -> [[Int16]] {
        var plane = [[Int16]](repeating: [Int16](repeating: 0, count: size), count: size)
        for h in 0..<size {
            for w in 0..<size {
                let (px, py) = boundaryRepeat((width / 2), (height / 2), (x + w), (y + h))
                plane[h][w] = self.cb[py][px]
            }
        }
        return plane
    }
    
    public func getCr(x: Int, y: Int, size: Int) -> [[Int16]] {
        var plane = [[Int16]](repeating: [Int16](repeating: 0, count: size), count: size)
        for h in 0..<size {
            for w in 0..<size {
                let (px, py) = boundaryRepeat((width / 2), (height / 2), (x + w), (y + h))
                plane[h][w] = self.cr[py][px]
            }
        }
        return plane
    }
    
    public mutating func updateY(data: [[Int16]], prediction: Int16, startX: Int, startY: Int, size: Int) {
        for h in 0..<size {
            if height <= (startY + h) {
                continue
            }
            for w in 0..<size {
                if width <= (startX + w) { // check bound
                    continue
                }
                self.y[startY + h][startX + w] = (data[h][w] + prediction)
            }
        }
    }
    
    public mutating func updateCb(data: [[Int16]], prediction: Int16, startX: Int, startY: Int, size: Int) {
        for h in 0..<size {
            if (height / 2) <= (startY + h) {
                continue
            }
            for w in 0..<size {
                if (width / 2) <= (startX + w) {
                     continue 
                }
                self.cb[startY + h][startX + w] = (data[h][w] + prediction)
            }
        }
    }
    
    public mutating func updateCr(data: [[Int16]], prediction: Int16, startX: Int, startY: Int, size: Int) {
        for h in 0..<size {
            if (height / 2) <= (startY + h) {
                continue
            }
            for w in 0..<size {
                 if (width / 2) <= (startX + w) {
                     continue 
                }
                self.cr[startY + h][startX + w] = (data[h][w] + prediction)
            }
        }
    }
    
    public func toYCbCr() -> YCbCrImage {
        var img = YCbCrImage(width: width, height: height)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = img.yOffset(x, y)
                img.yPlane[offset] = clampU8(self.y[y][x])
            }
        }
        
        for y in 0..<(height / 2) {
            for x in 0..<(width / 2) {
                let offset = img.cOffset(x, y)
                img.cbPlane[offset] = clampU8(self.cb[y][x])
                img.crPlane[offset] = clampU8(self.cr[y][x])
            }
        }
        return img
    }
}

// MARK: - Image Conversion Helper

public func pngToYCbCr(data: Data) throws -> YCbCrImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Image"])
    }
    
    let width = cgImage.width
    let height = cgImage.height
    // Use 4:4:4 to match Go implementation
    var ycbcr = YCbCrImage(width: width, height: height, ratio: .ratio444)
    
    guard let dataProvider = cgImage.dataProvider,
          let pixelData = dataProvider.data,
          let _ = CFDataGetBytePtr(pixelData) else {
        throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel data"])
    }
    
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bytesPerPixel = 4
    let bytesPerRow = (bytesPerPixel * width)
    var rawData = [UInt8](repeating: 0, count: (height * bytesPerRow))
    
    guard let context = CGContext(
        data: &rawData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
    }
    
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = ((y * bytesPerRow) + (x * bytesPerPixel))
            let r1 = Int32(rawData[offset + 0])
            let g1 = Int32(rawData[offset + 1])
            let b1 = Int32(rawData[offset + 2])
            
            let yVal = (19595 * r1 + 38470 * g1 + 7471 * b1 + (1 << 15)) >> 16
            let cbVal = ((-11059 * r1 - 21709 * g1 + 32768 * b1 + (1 << 15)) >> 16) + 128
            let crVal = ((32768 * r1 - 27439 * g1 - 5329 * b1 + (1 << 15)) >> 16) + 128
            
            let yIdx = ycbcr.yOffset(x, y)
            ycbcr.yPlane[yIdx] = UInt8(clamping: yVal)
            
            let cOff = ycbcr.cOffset(x, y) // Full resolution for 4:4:4
             if cOff < ycbcr.cbPlane.count {
                ycbcr.cbPlane[cOff] = UInt8(clamping: cbVal)
                ycbcr.crPlane[cOff] = UInt8(clamping: crVal)
            }
        }
    }
    
    return ycbcr
}

public func saveImage(img: YCbCrImage, url: URL) throws {
    let width = img.width
    let height = img.height
    let bytesPerPixel = 4
    let bytesPerRow = (bytesPerPixel * width)
    var rawData = [UInt8](repeating: 0, count: (height * bytesPerRow))
    
    for y in 0..<height {
        for x in 0..<width {
            let yVal = Float(img.yPlane[img.yOffset(x, y)])
            
            var cPx = x
            var cPy = y
            if img.ratio == .ratio420 {
                cPx = (x / 2)
                cPy = (y / 2)
            }
            
            let cOff = img.cOffset(cPx, cPy)
            let cbVal = Float(img.cbPlane[cOff]) - 128.0
            let crVal = Float(img.crPlane[cOff]) - 128.0
            
            let r = Int((yVal + (1.40200 * crVal)))
            let g = Int((yVal - (0.34414 * cbVal) - (0.71414 * crVal)))
            let b = Int((yVal + (1.77200 * cbVal)))
            
            let offset = ((y * bytesPerRow) + (x * bytesPerPixel))
            rawData[offset + 0] = UInt8(clamping: r)
            rawData[offset + 1] = UInt8(clamping: g)
            rawData[offset + 2] = UInt8(clamping: b)
            rawData[offset + 3] = 255 // Alpha
        }
    }
    
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: &rawData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw NSError(domain: "ImageError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context for output"])
    }
    
    guard let cgImage = context.makeImage() else {
        throw NSError(domain: "ImageError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
    }
    
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "ImageError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }
    
    CGImageDestinationAddImage(destination, cgImage, nil)
    if CGImageDestinationFinalize(destination) != true {
        throw NSError(domain: "ImageError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"])
    }
}
