import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Utilities

@inlinable @inline(__always)
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

@inlinable @inline(__always)
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

public enum YCbCrRatio: Sendable {
    case ratio420
    case ratio444
}

public struct YCbCrImage: Sendable {
    public var yPlane: [UInt8]
    public var cbPlane: [UInt8]
    public var crPlane: [UInt8]
    public let width: Int
    public let height: Int
    public let ratio: YCbCrRatio
    
    public var yStride: Int {
        @inlinable @inline(__always) get { width }
    }

    public var cStride: Int {
        @inlinable @inline(__always) get {
            switch ratio {
            case .ratio420: return (width + 1) / 2
            case .ratio444: return width
            }
        }
    }
    
    public init(width: Int, height: Int, ratio: YCbCrRatio = .ratio420) {
        self.width = width
        self.height = height
        self.ratio = ratio
        self.yPlane = [UInt8](repeating: 0, count: (width * height))
        
        switch ratio {
        case .ratio420:
             let cw = (width + 1) / 2
             let ch = (height + 1) / 2
             let cSize = (cw * ch)
            self.cbPlane = [UInt8](repeating: 0, count: cSize)
            self.crPlane = [UInt8](repeating: 0, count: cSize)
        case .ratio444:
            let cSize = (width * height)
            self.cbPlane = [UInt8](repeating: 0, count: cSize)
            self.crPlane = [UInt8](repeating: 0, count: cSize)
        }
    }
    
    @inlinable @inline(__always)
    public func yOffset(_ x: Int, _ y: Int) -> Int {
        return ((y * yStride) + x)
    }
    
    @inlinable @inline(__always)
    public func cOffset(_ x: Int, _ y: Int) -> Int {
        return ((y * cStride) + x)
    }

    @inline(__always)
    private func getChromaSize(w: Int, h: Int, ratio: YCbCrRatio) -> (Int, Int) {
        switch ratio {
        case .ratio420:
            return ((w + 1) / 2, (h + 1) / 2)
        case .ratio444:
            return (w, h)
        }
    }

    public func resize(factor: Double) -> YCbCrImage {
        let newWidth = Int(Double(width) * factor)
        let newHeight = Int(Double(height) * factor)

        guard 0 < newWidth && 0 < newHeight else {
            return YCbCrImage(width: max(1, newWidth), height: max(1, newHeight), ratio: self.ratio)
        }

        var dstImg = YCbCrImage(width: newWidth, height: newHeight, ratio: self.ratio)

        boxResizePlane(
            src: self.yPlane, srcW: self.width, srcH: self.height, srcStride: self.yStride,
            dst: &dstImg.yPlane, dstW: dstImg.width, dstH: dstImg.height, dstStride: dstImg.yStride
        )

        let (srcCW, srcCH) = getChromaSize(w: self.width, h: self.height, ratio: self.ratio)
        let (dstCW, dstCH) = getChromaSize(w: dstImg.width, h: dstImg.height, ratio: dstImg.ratio)

        // Cb
        boxResizePlane(
            src: self.cbPlane, srcW: srcCW, srcH: srcCH, srcStride: self.cStride,
            dst: &dstImg.cbPlane, dstW: dstCW, dstH: dstCH, dstStride: dstImg.cStride
        )

        // Cr
        boxResizePlane(
            src: self.crPlane, srcW: srcCW, srcH: srcCH, srcStride: self.cStride,
            dst: &dstImg.crPlane, dstW: dstCW, dstH: dstCH, dstStride: dstImg.cStride
        )

        return dstImg
    }

    private func boxResizePlane(
        src: [UInt8], srcW: Int, srcH: Int, srcStride: Int,
        dst: inout [UInt8], dstW: Int, dstH: Int, dstStride: Int
    ) {
        let scaleX = Double(srcW) / Double(dstW)
        let scaleY = Double(srcH) / Double(dstH)

        for dy in 0..<dstH {
            let syStart = Int(Double(dy) * scaleY)
            var syEnd = Int(Double(dy + 1) * scaleY)
            if srcH <= syEnd { syEnd = srcH }
            if syEnd <= syStart { syEnd = syStart + 1 }

            for dx in 0..<dstW {
                let sxStart = Int(Double(dx) * scaleX)
                var sxEnd = Int(Double(dx + 1) * scaleX)
                if srcW <= sxEnd { sxEnd = srcW }
                if sxEnd <= sxStart { sxEnd = sxStart + 1 }

                var sum: Int = 0
                var count: Int = 0

                for sy in syStart..<syEnd {
                    let rowOffset = sy * srcStride
                    for sx in sxStart..<sxEnd {
                        let srcIdx = rowOffset + sx
                        if srcIdx < src.count {
                            sum += Int(src[srcIdx])
                            count += 1
                        }
                    }
                }

                if 0 < count {
                    let dstIdx = (dy * dstStride) + dx
                    if dstIdx < dst.count {
                        dst[dstIdx] = UInt8(sum / count)
                    }
                }
            }
        }
    }
}

public typealias RowFunc = (_ x: Int, _ y: Int, _ size: Int) -> [Int16]

public struct ImageReader: Sendable {
    public let img: YCbCrImage
    public let width: Int
    public let height: Int
    
    public init(img: YCbCrImage) {
        self.img = img
        self.width = img.width
        self.height = img.height
    }
    
    public func rowY(x: Int, y: Int, size: Int) -> [Int16] {
        var plane = [Int16](repeating: 0, count: size)
        for i in 0..<size {
            let (px, py) = boundaryRepeat(width, height, (x + i), y)
            let offset = img.yOffset(px, py)
            plane[i] = Int16(img.yPlane[offset])
        }
        return plane
    }
    
    public func rowCb(x: Int, y: Int, size: Int) -> [Int16] {
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
            plane[i] = Int16(img.cbPlane[offset])
        }
        return plane
    }
    
    public func rowCr(x: Int, y: Int, size: Int) -> [Int16] {
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
            plane[i] = Int16(img.crPlane[offset])
        }
        return plane
    }
}

public struct Image16: Sendable {
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
    
    public func getY(x: Int, y: Int, size: Int) -> Block2D {
        let block = Block2D(width: size, height: size)
        for h in 0..<size {
            for w in 0..<size {
                let (px, py) = boundaryRepeat(width, height, (x + w), (y + h))
                block[h, w] = self.y[py][px]
            }
        }
        return block
    }
    
    public func getCb(x: Int, y: Int, size: Int) -> Block2D {
        let block = Block2D(width: size, height: size)
        for h in 0..<size {
            for w in 0..<size {
                let (px, py) = boundaryRepeat((width / 2), (height / 2), (x + w), (y + h))
                block[h, w] = self.cb[py][px]
            }
        }
        return block
    }
    
    public func getCr(x: Int, y: Int, size: Int) -> Block2D {
        let block = Block2D(width: size, height: size)
        for h in 0..<size {
            for w in 0..<size {
                let (px, py) = boundaryRepeat((width / 2), (height / 2), (x + w), (y + h))
                block[h, w] = self.cr[py][px]
            }
        }
        return block
    }
    
    public mutating func updateY(data: Block2D, startX: Int, startY: Int, size: Int) {
        let validStartY = max(0, startY)
        let validStartX = max(0, startX)
        let validEndY = min(height, startY + size)
        let validEndX = min(width, startX + size)
        
        let loopH = validEndY - validStartY
        let loopW = validEndX - validStartX
        
        if loopH <= 0 || loopW <= 0 { return }
        
        let dataOffsetY = validStartY - startY
        let dataOffsetX = validStartX - startX
        
        for h in 0..<loopH {
            self.y[validStartY + h].withUnsafeMutableBufferPointer { destPtr in
                data.withUnsafeBufferPointer(atRow: dataOffsetY + h) { srcPtr in
                    guard let destBase = destPtr.baseAddress,
                          let srcBase = srcPtr.baseAddress else { return }
                    
                    let destStart = destBase.advanced(by: validStartX)
                    let srcStart = srcBase.advanced(by: dataOffsetX)
                    destStart.update(from: srcStart, count: loopW)
                }
            }
        }
    }
    
    public mutating func updateCb(data: Block2D, startX: Int, startY: Int, size: Int) {
        let halfHeight = (height / 2)
        let halfWidth = (width / 2)
        
        let validStartY = max(0, startY)
        let validStartX = max(0, startX)
        let validEndY = min(halfHeight, startY + size)
        let validEndX = min(halfWidth, startX + size)
        
        let loopH = validEndY - validStartY
        let loopW = validEndX - validStartX
        
        if loopH <= 0 || loopW <= 0 { return }
        
        let dataOffsetY = validStartY - startY
        let dataOffsetX = validStartX - startX
        
        for h in 0..<loopH {
            self.cb[validStartY + h].withUnsafeMutableBufferPointer { destPtr in
                data.withUnsafeBufferPointer(atRow: dataOffsetY + h) { srcPtr in
                    guard let destBase = destPtr.baseAddress,
                          let srcBase = srcPtr.baseAddress else { return }
                    
                    let destStart = destBase.advanced(by: validStartX)
                    let srcStart = srcBase.advanced(by: dataOffsetX)
                    destStart.update(from: srcStart, count: loopW)
                }
            }
        }
    }
    
    public mutating func updateCr(data: Block2D, startX: Int, startY: Int, size: Int) {
        let halfHeight = (height / 2)
        let halfWidth = (width / 2)
        
        let validStartY = max(0, startY)
        let validStartX = max(0, startX)
        let validEndY = min(halfHeight, startY + size)
        let validEndX = min(halfWidth, startX + size)
        
        let loopH = validEndY - validStartY
        let loopW = validEndX - validStartX
        
        if loopH <= 0 || loopW <= 0 { return }
        
        let dataOffsetY = validStartY - startY
        let dataOffsetX = validStartX - startX
        
        for h in 0..<loopH {
            self.cr[validStartY + h].withUnsafeMutableBufferPointer { destPtr in
                data.withUnsafeBufferPointer(atRow: dataOffsetY + h) { srcPtr in
                    guard let destBase = destPtr.baseAddress,
                          let srcBase = srcPtr.baseAddress else { return }
                    
                    let destStart = destBase.advanced(by: validStartX)
                    let srcStart = srcBase.advanced(by: dataOffsetX)
                    destStart.update(from: srcStart, count: loopW)
                }
            }
        }
    }
    
    public func toYCbCr() -> YCbCrImage {
        var img = YCbCrImage(width: width, height: height)
        
        for y in 0..<height {
            let srcRow = self.y[y]
            let destOffset = img.yOffset(0, y)
            
            srcRow.withUnsafeBufferPointer { srcPtr in
                img.yPlane.withUnsafeMutableBufferPointer { destPtr in
                    guard let srcBase = srcPtr.baseAddress,
                          let destBase = destPtr.baseAddress else { return }
                    
                    let destRowStart = destBase.advanced(by: destOffset)
                    
                    for i in 0..<width {
                        destRowStart[i] = clampU8(srcBase[i])
                    }
                }
            }
        }
        
        let halfHeight = height / 2
        let halfWidth = width / 2
        
        for y in 0..<halfHeight {
            let srcCbRow = self.cb[y]
            let srcCrRow = self.cr[y]
            let destOffset = img.cOffset(0, y)
            
            srcCbRow.withUnsafeBufferPointer { cbPtr in
                srcCrRow.withUnsafeBufferPointer { crPtr in
                    img.cbPlane.withUnsafeMutableBufferPointer { destCbPtr in
                        img.crPlane.withUnsafeMutableBufferPointer { destCrPtr in
                            guard let cbBase = cbPtr.baseAddress,
                                  let crBase = crPtr.baseAddress,
                                  let destCbBase = destCbPtr.baseAddress,
                                  let destCrBase = destCrPtr.baseAddress else { return }
                            
                            let destCbRowStart = destCbBase.advanced(by: destOffset)
                            let destCrRowStart = destCrBase.advanced(by: destOffset)
                            
                            for i in 0..<halfWidth {
                                destCbRowStart[i] = clampU8(cbBase[i])
                                destCrRowStart[i] = clampU8(crBase[i])
                            }
                        }
                    }
                }
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
    // Use 4:4:4
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
            let yScaled = Int(img.yPlane[img.yOffset(x, y)]) << 10
            
            var cPx = x
            var cPy = y
            if img.ratio == .ratio420 {
                cPx = (x / 2)
                cPy = (y / 2)
            }
            
            let cOff = img.cOffset(cPx, cPy)
            let cbDiff = Int(img.cbPlane[cOff]) - 128
            let crDiff = Int(img.crPlane[cOff]) - 128
            
            let r = (yScaled + (1436 * crDiff)) >> 10
            let g = (yScaled - (352 * cbDiff) - (731 * crDiff)) >> 10
            let b = (yScaled + (1815 * cbDiff)) >> 10
            
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
