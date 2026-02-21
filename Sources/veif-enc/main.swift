import Foundation
import PNG
import veif

let args = CommandLine.arguments
var bitrate = 200
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
    default:
        positionalArgs.append(arg)
    }
    i += 1
}

let srcPath = (0 < positionalArgs.count) ? positionalArgs[0] : "src.png"
let outDir = (1 < positionalArgs.count) ? positionalArgs[1] : "."

let srcURL = URL(fileURLWithPath: srcPath)
let basename = srcURL.lastPathComponent.replacingOccurrences(of: "." + srcURL.pathExtension, with: "")
let outPath = "\(outDir)/\(basename).veif"

guard let image:PNG.Image = try .decompress(path: srcPath) else {
    print("Failed to decode \(srcPath)")
    exit(1)
}

let rgba:[PNG.RGBA<UInt8>] = image.unpack(as: PNG.RGBA<UInt8>.self)
var data = [UInt8](repeating: 0, count: rgba.count * 4)
rgba.withUnsafeBufferPointer { rgbaPtr in
    data.withUnsafeMutableBufferPointer { dataPtr in
        let rgbaBase = rgbaPtr.baseAddress!
        let dataBase = dataPtr.baseAddress!
        let totalPixels = rgba.count
        for i in 0..<totalPixels {
            let offset = i * 4
            dataBase[offset + 0] = rgbaBase[i].r
            dataBase[offset + 1] = rgbaBase[i].g
            dataBase[offset + 2] = rgbaBase[i].b
            dataBase[offset + 3] = rgbaBase[i].a
        }
    }
}

let ycbcr = veif.rgbaToYCbCr(data: data, width: image.size.x, height: image.size.y)
do {
    let startTime = Date()
    let out: [UInt8] = try await veif.encode(img:ycbcr, maxbitrate: bitrate * 1000)
    let elapsed = Date().timeIntervalSince(startTime)
    print(String(
        format:"elapse=%.4fms %3.2fKB -> %3.2fKB compressed %3.2f%%",
        elapsed * 1000,
        Double(data.count) / 1024.0,
        Double(out.count) / 1024.0,
        Double(out.count) / Double(data.count) * 100.0,
    ))

    if FileManager.default.createFile(atPath: outPath, contents: Data(out)) {
        print("Successfully encoded \(srcPath) to \(outPath)")
    } else {
        print("Failed to write \(outPath)")
        exit(1)
    }
} catch {
    print("Failed to encode \(srcPath)")
    exit(1)
}