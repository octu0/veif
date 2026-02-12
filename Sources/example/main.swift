import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import veif

// MARK: - Benchmark

func runBenchmark(srcURL: URL) {
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

    print("\n=== JPEG Comparison ===")
    for q in stride(from: 50, through: 100, by: 10) {
        runJPEGComparison(q: q, refLarge: refLarge, refMid: refMid, refSmall: refSmall)
    }

    print("\n=== Custom Codec Comparison ===")
    for bitrate in stride(from: 100, through: 500, by: 100) {
        runCustomCodecComparison(bitrate: bitrate, originImg: originImg, refMid: refMid, refSmall: refSmall)
    }
}

func runJPEGComparison(q: Int, refLarge: YCbCrImage, refMid: YCbCrImage, refSmall: YCbCrImage) {
    guard let cgImage = yCbCrToCGImage(img: refLarge) else { return }

    let dstData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(dstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return }

    let options = [kCGImageDestinationLossyCompressionQuality: (Double(q) / 100.0)] as CFDictionary
    CGImageDestinationAddImage(destination, cgImage, options)
    CGImageDestinationFinalize(destination)

    let encodedBytes = dstData as Data
    let sizeKB = (Double(encodedBytes.count) / 1024.0)

    guard let decodedYCbCr = try? pngToYCbCr(data: encodedBytes) else { return }

    let jpgLarge = decodedYCbCr
    let jpgMid = resizeHalfNN(jpgLarge)
    let jpgSmall = resizeHalfNN(jpgMid)

    let l = calcMetrics(ref: refLarge, target: jpgLarge)
    let m = calcMetrics(ref: refMid, target: jpgMid)
    let s = calcMetrics(ref: refSmall, target: jpgSmall)

    printMetrics(prefix: "JPEG Q", val: q, sizeKB: sizeKB, l: l, m: m, s: s)
}

func runCustomCodecComparison(bitrate: Int, originImg: YCbCrImage, refMid: YCbCrImage, refSmall: YCbCrImage) {
    let targetBits = (bitrate * 1000)

    guard let out = try? encode(img: originImg, maxbitrate: targetBits) else {
        fatalError("Failed to encode")
    }

    let sizeKB = (Double(out.count) / 1024.0)

    guard let (decSmall, decMid, decLarge) = try? decode(r: out) else {
        fatalError("Failed to decode")
    }

    let l = calcMetrics(ref: originImg, target: decLarge)
    let m = calcMetrics(ref: refMid, target: decMid)
    let s = calcMetrics(ref: refSmall, target: decSmall)

    printMetrics(prefix: "MY   Rate", val: bitrate, sizeKB: sizeKB, l: l, m: m, s: s)
}

func printMetrics(prefix: String, val: Int, sizeKB: Double, l: BenchmarkMetrics, m: BenchmarkMetrics, s: BenchmarkMetrics) {
    if prefix == "JPEG Q" {
        print(String(format: "%@=%3d Size=%6.2fKB", prefix, val, sizeKB))
    } else {
        print(String(format: "%@=%4d k Size=%6.2fKB", prefix, val, sizeKB))
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
            let cbVal = Float(img.cbPlane[img.cOffset((x / 2), (y / 2))]) - 128.0
            let crVal = Float(img.crPlane[img.cOffset((x / 2), (y / 2))]) - 128.0

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

// MARK: - Main Entry Point

let args = CommandLine.arguments
var bitrate = 100
var benchmarkMode = false
var positionalArgs: [String] = []

var i = 1
while i < args.count {
    let arg = args[i]
    
    switch arg {
    case "-bitrate":
        if (i + 1) < args.count {
            if let v = Int(args[i + 1]) {
                bitrate = v
            }
            i += 1
        }
    case "-benchmark":
        benchmarkMode = true
    default:
        positionalArgs.append(arg)
    }
    i += 1
}

let srcPath = (0 < positionalArgs.count) ? positionalArgs[0] : "src.png"
let outDir = (1 < positionalArgs.count) ? positionalArgs[1] : "."
let srcURL = URL(fileURLWithPath: srcPath)
let outURL = URL(fileURLWithPath: outDir, isDirectory: true)

// Create output directory if it doesn't exist
if FileManager.default.fileExists(atPath: outURL.path) != true {
    try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
}

if benchmarkMode == true {
    runBenchmark(srcURL: srcURL)
    exit(0)
}

guard let data = try? Data(contentsOf: srcURL) else {
    print("Failed to read \(srcURL.path)")
    exit(1)
}

guard let ycbcr = try? pngToYCbCr(data: data) else {
    print("Failed to decode \(srcURL.path)")
    exit(1)
}

let srcbit = (ycbcr.width * ycbcr.height * 8)
let maxbit = (bitrate * 1000)
print("src \(srcbit) bit")
print(String(format: "target %d bit = %3.2f%%", maxbit, ((Double(maxbit) / Double(srcbit)) * 100)))

let startTime = Date()
// Ensure encode exists in veif and is accessible
guard let out = try? encode(img: ycbcr, maxbitrate: (bitrate * 1000)) else {
    print("Failed to encode")
    exit(1)
}
let elapsed = Date().timeIntervalSince(startTime)

func readLayerSizes(data: Data) -> (Int, Int, Int) {
    var offset = 0
    func readLen() -> Int {
        let val = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4
        return Int(val)
    }

    let len0 = readLen()
    offset += len0
    let len1 = readLen()
    offset += len1
    let len2 = readLen()

    return (len0, len1, len2)
}

let (l0Size, l1Size, l2Size) = readLayerSizes(data: out)
let totalSize = out.count

let originalSize = (ycbcr.yPlane.count + ycbcr.cbPlane.count + ycbcr.crPlane.count)
let compressedSize = totalSize

print(String(
    format: "elapse=%.4fs %3.2fKB -> %3.2fKB compressed %3.2f%%",
    elapsed,
    (Double(originalSize) / 1024.0),
    (Double(compressedSize) / 1024.0),
    ((Double(compressedSize) / Double(originalSize)) * 100)
))

guard let (layer0, layer1, layer2) = try? decode(r: out) else {
    print("Failed to decode")
    exit(1)
}

func fmtSize(_ size: Int) -> String {
    return String(format: "%.2fKB", (Double(size) / 1024.0))
}

try? saveImage(img: layer0, url: outURL.appendingPathComponent("out_layer0.png"))

let s0 = (4 + l0Size)
let s1 = ((s0 + 4) + l1Size)
let s2 = ((s1 + 4) + l2Size)

print("| Layer0 | 1/4 | \(fmtSize(s0)) |")

try? saveImage(img: layer1, url: outURL.appendingPathComponent("out_layer1.png"))
print("| Layer1 | 1/2 | \(fmtSize(s1)) |")

try? saveImage(img: layer2, url: outURL.appendingPathComponent("out_layer2.png"))
print("| Layer2 | 1 | \(fmtSize(s2)) |")

let srcFileSize = (try? Data(contentsOf: srcURL).count) ?? 0
print("| original | 1 | \(fmtSize(srcFileSize)) |")
