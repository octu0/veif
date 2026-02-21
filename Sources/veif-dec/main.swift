import Foundation
import PNG
import veif

let args = CommandLine.arguments
var positionalArgs: [String] = []

var i = 1
while i < args.count {
    let arg = args[i]
    positionalArgs.append(arg)
    i += 1
}

let srcPath = (0 < positionalArgs.count) ? positionalArgs[0] : "src.veif"
let outDir = (1 < positionalArgs.count) ? positionalArgs[1] : "."

let srcURL = URL(fileURLWithPath: srcPath)
let basename = srcURL.lastPathComponent.replacingOccurrences(of: "." + srcURL.pathExtension, with: "")
let out0Path = "\(outDir)/\(basename).0.png"
let out1Path = "\(outDir)/\(basename).1.png"
let out2Path = "\(outDir)/\(basename).2.png"

guard let data = FileManager.default.contents(atPath: srcPath) else {
    print("Failed to read \(srcPath)")
    exit(1)
}

do {
    let startTime = Date()
    let (layer0, layer1, layer2) = try await veif.decodeImage(r: data)
    let elapsed = Date().timeIntervalSince(startTime)

    let rgba0 = veif.ycbcrToRGBA(img: layer0)
    var rgba0_png = [PNG.RGBA<UInt8>]()
    for i in stride(from: 0, to: rgba0.count, by: 4) {
        rgba0_png.append(PNG.RGBA<UInt8>(rgba0[i], rgba0[i + 1], rgba0[i + 2], rgba0[i + 3]))
    }

    let rgba1 = veif.ycbcrToRGBA(img: layer1)
    var rgba1_png = [PNG.RGBA<UInt8>]()
    for i in stride(from: 0, to: rgba1.count, by: 4) {
        rgba1_png.append(PNG.RGBA<UInt8>(rgba1[i], rgba1[i + 1], rgba1[i + 2], rgba1[i + 3]))
    }

    let rgba2 = veif.ycbcrToRGBA(img: layer2)
    var rgba2_png = [PNG.RGBA<UInt8>]()
    for i in stride(from: 0, to: rgba2.count, by: 4) {
        rgba2_png.append(PNG.RGBA<UInt8>(rgba2[i], rgba2[i + 1], rgba2[i + 2], rgba2[i + 3]))
    }
    
    print(String(
        format:"elapse=%.4fms %3.2fKB -> %3.2fKB",
        elapsed * 1000,
        Double(data.count) / 1024.0,
        Double(rgba2.count) / 1024.0,
    ))

    let size0:(x:Int, y:Int) = (x:layer0.width, y:layer0.height)
    let size1:(x:Int, y:Int) = (x:layer1.width, y:layer1.height)
    let size2:(x:Int, y:Int) = (x:layer2.width, y:layer2.height)
    let layout:PNG.Layout = .init(format: .rgba8(palette: [], fill: nil))

    try PNG.Image(packing: rgba0_png, size: size0, layout: layout).compress(path: out0Path)
    print("out layer0 Path: \(out0Path)")
    try PNG.Image(packing: rgba1_png, size: size1, layout: layout).compress(path: out1Path)
    print("out layer1 Path: \(out1Path)")
    try PNG.Image(packing: rgba2_png, size: size2, layout: layout).compress(path: out2Path)
    print("out layer2 Path: \(out2Path)")
} catch {
    print("Failed to decode \(srcPath)")
    exit(1)
}