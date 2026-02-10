import veif
import Foundation

let args = ProcessInfo.processInfo.arguments

if args.count < 3 {
    print("Usage: run <input_file> <output_dir>")
    exit(1)
}

let inputPath = args[1]
let outputDir = args[2]

print("Loading image from \(inputPath)")
let inputURL = URL(fileURLWithPath: inputPath)
guard let img = Image16(url: inputURL) else {
    print("Failed to load image")
    exit(1)
}

print("Image loaded: \(img.width)x\(img.height)")

// Encode
print("Start Encode")
let startTime = Date()
let (layer0, layer1, layer2) = encode(img: img, maxbitrate: 200000)
let elapsed = Date().timeIntervalSince(startTime)

let l0Size = layer0.count
let l1Size = layer1.count
let l2Size = layer2.count
let totalSize = l0Size + l1Size + l2Size
let originalSize = (img.width * img.height + (img.width/2 * img.height/2) * 2) * 2 // Raw YUV size (approx, assuming 8-bit input)

let compressionRatio = (Double(totalSize) / Double(originalSize)) * 100.0

print(String(format: "elapse=%.4fs", elapsed))
print(String(format: "Layer0: %.2fKB", Double(l0Size) / 1024.0))
print(String(format: "Layer1: %.2fKB", Double(l1Size) / 1024.0))
print(String(format: "Layer2: %.2fKB", Double(l2Size) / 1024.0))
print(String(format: "Total: %.2fKB -> %.2fKB (Compressed %.2f%%)", Double(originalSize) / 1024.0, Double(totalSize) / 1024.0, compressionRatio))

// Helper to save image
func save(image: Image16, to path: String) {
    let url = URL(fileURLWithPath: path)
    if image.save(to: url) {
        print("Scucess to save \(path)")
    } else {
        print("Failed to save \(path)")
    }
}

// Decode Layer 0
let img0 = try decode(layers: [layer0])
save(image: img0, to: "\(outputDir)/out_layer0.png")
print("Layer0 decoded size: \(img0.width)x\(img0.height)")

// Decode Layer 0 + 1
let img1 = try decode(layers: [layer0, layer1])
save(image: img1, to: "\(outputDir)/out_layer1.png")
print("Layer1 decoded size: \(img1.width)x\(img1.height)")

// Decode Layer 0 + 1 + 2 (Full)
let img2 = try decode(layers: [layer0, layer1, layer2])
save(image: img2, to: "\(outputDir)/out_layer2.png")
print("Layer2 decoded size: \(img2.width)x\(img2.height)")
