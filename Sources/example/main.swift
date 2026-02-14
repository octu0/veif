import Foundation
import veif

// MARK: - Main Entry Point

let args = CommandLine.arguments
var bitrate = 200
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
    await runBenchmark(srcURL: srcURL)
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

let srcbit = ((ycbcr.yPlane.count + ycbcr.cbPlane.count + ycbcr.crPlane.count) * 8)
let maxbit = (bitrate * 1000)
print("src \(srcbit) bit")
print(String(format: "target %d bit = %3.2f%%", maxbit, ((Double(maxbit) / Double(srcbit)) * 100)))

let startTime = Date()
// Ensure encode exists in veif and is accessible
guard let out = try? await encode(img: ycbcr, maxbitrate: (bitrate * 1000)) else {
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
    format: "elapse=%.4fms %3.2fKB -> %3.2fKB compressed %3.2f%%",
    elapsed * 1000.0,
    (Double(originalSize) / 1024.0),
    (Double(compressedSize) / 1024.0),
    ((Double(compressedSize) / Double(originalSize)) * 100)
))

guard let (layer0, layer1, layer2) = try? await decode(r: out) else {
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

