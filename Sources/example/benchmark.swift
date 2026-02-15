import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import veif

// MARK: - Benchmark

func runBenchmark(srcURL: URL) async {
    guard let data = try? Data(contentsOf: srcURL) else {
        fatalError("Failed to read src.png")
    }

    // Convert to YCbCrImage
    guard let ycbcr = try? pngToYCbCr(data: data) else {
        fatalError("Failed to decode src.png")
    }

    let originImg = ycbcr

    // Prepare Reference Images
    let refLarge = originImg
    let refMid = resizeHalfNN(refLarge)
    let refSmall = resizeHalfNN(refMid)

    print("Reference: Large=\(refLarge.width)x\(refLarge.height) Mid=\(refMid.width)x\(refMid.height) Small=\(refSmall.width)x\(refSmall.height)")

    print("\n### Single Size ###")

    print("\n=== JPEG Comparison ===")
    for q in stride(from: 50, through: 100, by: 10) {
        runJPEGSingleSizeComparison(q: q, refLarge: refLarge)
    }

    print("\n=== Custom Codec Comparison ===")
    for bitrate in stride(from: 50, through: 300, by: 50) {
        await runCustomCodecOneComparison(bitrate: bitrate, originImg: originImg)
    }

    print("\n### Multi Size ###")

    print("\n=== JPEG Comparison ===")
    for q in stride(from: 50, through: 100, by: 10) {
        runJPEGMultiSizeComparison(q: q, refLarge: refLarge, refMid: refMid, refSmall: refSmall)
    }

    print("\n=== Custom Codec Comparison ===")
    for bitrate in stride(from: 50, through: 300, by: 50) {
        await runCustomCodecLayersComparison(bitrate: bitrate, originImg: originImg, refMid: refMid, refSmall: refSmall)
    }
}

func runJPEGSingleSizeComparison(q: Int, refLarge: YCbCrImage) {
    guard let cgImage = yCbCrToCGImage(img: refLarge) else { return }

    let iterations = 100
    var totalDuration: Double = 0
    let options = [kCGImageDestinationLossyCompressionQuality: (Double(q) / 100.0)] as CFDictionary

    let firstDstData = NSMutableData()
    guard let firstDest = CGImageDestinationCreateWithData(firstDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(firstDest, cgImage, options)
    if CGImageDestinationFinalize(firstDest) == false { return }
    let encodedBytes = firstDstData as Data

    for _ in 0..<iterations {
        let loopDstData = NSMutableData()
        guard let loopDest = CGImageDestinationCreateWithData(loopDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
        let start = CFAbsoluteTimeGetCurrent()
        CGImageDestinationAddImage(loopDest, cgImage, options)
        CGImageDestinationFinalize(loopDest)
        totalDuration += (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }
    let duration = totalDuration / Double(iterations)
    let sizeKB = (Double(encodedBytes.count) / 1024.0)

    guard let decodedYCbCr = try? pngToYCbCr(data: encodedBytes) else { return }

    let jpgLarge = decodedYCbCr

    let l = calcMetrics(ref: refLarge, target: jpgLarge)

    printSingleMetrics(prefix: "JPEG Q", val: q, sizeKB: sizeKB, duration: duration, l: l)
}

func runJPEGMultiSizeComparison(q: Int, refLarge: YCbCrImage, refMid: YCbCrImage, refSmall: YCbCrImage) {
    guard let cgImage = yCbCrToCGImage(img: refLarge) else { return }

    let iterations = 100
    var totalDuration: Double = 0
    let options = [kCGImageDestinationLossyCompressionQuality: (Double(q) / 100.0)] as CFDictionary

    let firstDstData = NSMutableData()
    guard let firstDest = CGImageDestinationCreateWithData(firstDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(firstDest, cgImage, options)
    if CGImageDestinationFinalize(firstDest) == false { return }
    let encodedBytes = firstDstData as Data

    for _ in 0..<iterations {
        let loopDstData = NSMutableData()
        guard let loopDest = CGImageDestinationCreateWithData(loopDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
        let start = CFAbsoluteTimeGetCurrent()
        CGImageDestinationAddImage(loopDest, cgImage, options)
        CGImageDestinationFinalize(loopDest)
        totalDuration += (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }
    let duration = totalDuration / Double(iterations)
    let sizeKB = (Double(encodedBytes.count) / 1024.0)

    guard let decodedYCbCr = try? pngToYCbCr(data: encodedBytes) else { return }

    let jpgLarge = decodedYCbCr
    let jpgMid = resizeHalfNN(jpgLarge)
    let jpgSmall = resizeHalfNN(jpgMid)

    let l = calcMetrics(ref: refLarge, target: jpgLarge)
    let m = calcMetrics(ref: refMid, target: jpgMid)
    let s = calcMetrics(ref: refSmall, target: jpgSmall)

    printMultiMetrics(prefix: "JPEG Q", val: q, sizeKB: sizeKB, duration: duration, l: l, m: m, s: s)
}


func runCustomCodecOneComparison(bitrate: Int, originImg: YCbCrImage) async {
    let targetBits = (bitrate * 1000)

    let iterations = 100
    var totalDuration: Double = 0
    
    guard let out = try? await encodeOne(img: originImg, maxbitrate: targetBits) else {
        fatalError("Failed to encode")
    }

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? await encodeOne(img: originImg, maxbitrate: targetBits)
        totalDuration += (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }
    let duration = totalDuration / Double(iterations)

    let sizeKB = (Double(out.count) / 1024.0)

    guard let decLarge = try? await decodeOne(r: out) else {
        fatalError("Failed to decode")
    }

    let l = calcMetrics(ref: originImg, target: decLarge)

    printSingleMetrics(prefix: "MY   Rate", val: bitrate, sizeKB: sizeKB, duration: duration, l: l)
}

func runCustomCodecLayersComparison(bitrate: Int, originImg: YCbCrImage, refMid: YCbCrImage, refSmall: YCbCrImage) async {
    let targetBits = (bitrate * 1000)

    let iterations = 100
    var totalDuration: Double = 0
    
    guard let out = try? await encode(img: originImg, maxbitrate: targetBits) else {
        fatalError("Failed to encode")
    }

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? await encode(img: originImg, maxbitrate: targetBits)
        totalDuration += (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }
    let duration = totalDuration / Double(iterations)

    let sizeKB = (Double(out.count) / 1024.0)

    guard let (decSmall, decMid, decLarge) = try? await decode(r: out) else {
        fatalError("Failed to decode")
    }

    let l = calcMetrics(ref: originImg, target: decLarge)
    let m = calcMetrics(ref: refMid, target: decMid)
    let s = calcMetrics(ref: refSmall, target: decSmall)

    printMultiMetrics(prefix: "MY   Rate", val: bitrate, sizeKB: sizeKB, duration: duration, l: l, m: m, s: s)
}

func printSingleMetrics(prefix: String, val: Int, sizeKB: Double, duration: Double, l: BenchmarkMetrics) {
    if prefix == "JPEG Q" {
        print(String(format: "%@=%3d Size=%6.2fKB Time=%6.2fms", prefix, val, sizeKB, duration))
    } else {
        print(String(format: "%@=%4d k Size=%6.2fKB Time=%6.2fms", prefix, val, sizeKB, duration))
    }

    printLayerMetric(label: "L", m: l)
}

func printMultiMetrics(prefix: String, val: Int, sizeKB: Double, duration: Double, l: BenchmarkMetrics, m: BenchmarkMetrics, s: BenchmarkMetrics) {
    if prefix == "JPEG Q" {
        print(String(format: "%@=%3d Size=%6.2fKB Time=%6.2fms", prefix, val, sizeKB, duration))
    } else {
        print(String(format: "%@=%4d k Size=%6.2fKB Time=%6.2fms", prefix, val, sizeKB, duration))
    }

    printLayerMetric(label: "L", m: l)
    printLayerMetric(label: "M", m: m)
    printLayerMetric(label: "S", m: s)
}

func printLayerMetric(label: String, m: BenchmarkMetrics) {
    print(String(
        format: " [%@] PSNR=%.2f SSIM=%.4f MS-SSIM=%.4f (Y:%.2f Cb:%.2f Cr:%.2f)",
        label, m.psnr, m.ssim, m.msssim, m.y, m.cb, m.cr
    ))
}

// MARK: - Helper for Benchmark

func yCbCrToCGImage(img: YCbCrImage) -> CGImage? {
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
            rawData[offset + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &rawData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }

    return context.makeImage()
}