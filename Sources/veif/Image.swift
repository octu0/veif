import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public class Image16 {
    public var yPlane: [Int16]
    public var cbPlane: [Int16]
    public var crPlane: [Int16]
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.yPlane = [Int16](repeating: 0, count: width * height)
        self.cbPlane = [Int16](repeating: 0, count: (width / 2) * (height / 2))
        self.crPlane = [Int16](repeating: 0, count: (width / 2) * (height / 2))
    }

    public func yOffset(x: Int, y: Int) -> Int {
        return y * self.width + x
    }

    public func cOffset(x: Int, y: Int) -> Int {
        return y * (self.width / 2) + x
    }

    public func copy() -> Image16 {
        let newImg = Image16(width: self.width, height: self.height)
        newImg.yPlane = self.yPlane
        newImg.cbPlane = self.cbPlane
        newImg.crPlane = self.crPlane
        return newImg
    }

    // MARK: - ImageIO Extensions

    public convenience init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        self.init(cgImage: cgImage)
    }

    public convenience init(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        self.init(width: width, height: height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue)

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // RGB -> YCbCr
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(rawData[offset])
                let g = Double(rawData[offset + 1])
                let b = Double(rawData[offset + 2])

                let yVal = 0.299 * r + 0.587 * g + 0.114 * b
                let cbVal = -0.1687 * r - 0.3313 * g + 0.5 * b + 128
                let crVal = 0.5 * r - 0.4187 * g - 0.0813 * b + 128

                self.yPlane[self.yOffset(x: x, y: y)] = Int16(yVal)

                if x % 2 == 0 && y % 2 == 0 {
                    let cx = x / 2
                    let cy = y / 2
                    if cx < width / 2 && cy < height / 2 {
                        self.cbPlane[self.cOffset(x: cx, y: cy)] = Int16(cbVal)
                        self.crPlane[self.cOffset(x: cx, y: cy)] = Int16(crVal)
                    }
                }
            }
        }
    }

    public func toCGImage() -> CGImage? {
        let width = self.width
        let height = self.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let yVal = Double(self.yPlane[self.yOffset(x: x, y: y)])

                let cx = x / 2
                let cy = y / 2
                var cbVal: Double = 128
                var crVal: Double = 128

                if cx < width / 2 && cy < height / 2 {
                    cbVal = Double(self.cbPlane[self.cOffset(x: cx, y: cy)])
                    crVal = Double(self.crPlane[self.cOffset(x: cx, y: cy)])
                }

                let r = yVal + 1.402 * (crVal - 128)
                let g = yVal - 0.34414 * (cbVal - 128) - 0.71414 * (crVal - 128)
                let b = yVal + 1.772 * (cbVal - 128)

                let offset = y * bytesPerRow + x * bytesPerPixel
                rawData[offset] = clamp(r)
                rawData[offset + 1] = clamp(g)
                rawData[offset + 2] = clamp(b)
                rawData[offset + 3] = 255  // Alpha
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )

        return context?.makeImage()
    }

    private func clamp(_ v: Double) -> UInt8 {
        if v < 0 { return 0 }
        if 255 < v { return 255 }
        return UInt8(v)
    }

    public func save(to url: URL) -> Bool {
        guard let cgImage = self.toCGImage() else { return false }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination)
    }
}
