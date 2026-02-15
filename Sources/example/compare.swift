import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import veif

// MARK: - Compare

func runCompare(srcURL: URL, outURL: URL) async {
    guard let data = try? Data(contentsOf: srcURL) else {
        fatalError("Failed to read src.png")
    }

    // Convert to YCbCrImage
    guard let ycbcr = try? pngToYCbCr(data: data) else {
        fatalError("Failed to decode src.png")
    }
    let originImg = ycbcr

    print("Comparison Start: Source=\(originImg.width)x\(originImg.height)")

    // --- Collect Data Points ---
    
    var jpegPoints: [(Double, Double, Double, Double)] = [] // (SizeKB, MS-SSIM, EncTime, DecTime)
    print("\n=== JPEG Collection ===")
    // Quality 10...100 (step 5)
    for q in stride(from: 10, through: 100, by: 5) {
        if let p = runJPEGSinglePoint(q: q, originImg: originImg) {
            jpegPoints.append(p)
            print(String(format: "Q=%3d Size=%6.2fKB MS-SSIM=%.4f Enc=%.2fms Dec=%.2fms", q, p.0, p.1, p.2, p.3))
        }
    }
    
    var veifPoints: [(Double, Double, Double, Double)] = [] // (SizeKB, MS-SSIM, EncTime, DecTime)
    print("\n=== veif Collection ===")
    // Bitrate 50...300 (step 10)
    for bitrate in stride(from: 50, through: 300, by: 10) {
        if let p = await runVeifSinglePoint(bitrate: bitrate, originImg: originImg) {
            veifPoints.append(p)
            print(String(format: "Rate=%3dk Size=%6.2fKB MS-SSIM=%.4f Enc=%.2fms Dec=%.2fms", bitrate, p.0, p.1, p.2, p.3))
        }
    }
    
    // --- Thumbnail Speed Graph (Total: Orig + Thumb) ---
    // User requested: "compare_total_thumbnail_ms-ssim.png で保存するようにして、既存のロジックは触らずに追加してほしい"
    
    print("\n=== Thumbnail Collection ===")
    
    var jpegThumbPoints: [(Double, Double, Double, Double)] = [] // (ThumbSizeKB, ThumbSSIM, ThumbEncTime, ThumbDecTime)
    // Reuse existing JPEG Q loop range
    for q in stride(from: 10, through: 100, by: 5) {
        if let p = runJPEGThumbnailSinglePoint(q: q, originImg: originImg) {
             jpegThumbPoints.append(p)
             print(String(format: "Q=%3d Thumb: Size=%6.2fKB SSIM=%.4f Enc=%.2fms Dec=%.2fms", q, p.0, p.1, p.2, p.3))
        }
    }
    
    // Reuse existing veif Bitrate loop range
    var veifThumbPoints: [(Double, Double, Double, Double)] = []
    for bitrate in stride(from: 50, through: 300, by: 10) {
        if let p = await runVeifThumbnailSinglePoint(bitrate: bitrate, originImg: originImg) {
            veifThumbPoints.append(p)
            print(String(format: "Rate=%3dk Thumb: Size=%6.2fKB SSIM=%.4f Enc=%.2fms Dec=%.2fms", bitrate, p.0, p.1, p.2, p.3))
        }
    }

    // --- Draw Quality Graph (Size vs MS-SSIM) ---
    
    print("\nGenerating Quality Graph...")
    // Extract (Size, MS-SSIM) for existing graph
    let jpegQualityPoints = jpegPoints.map { ($0.0, $0.1) }
    let veifQualityPoints = veifPoints.map { ($0.0, $0.1) }
    
    if let graphImg = drawComparisonGraph(title: "Quality Comparison: JPEG vs veif", jpegPoints: jpegQualityPoints, veifPoints: veifQualityPoints) {
        let fileURL = outURL.appendingPathComponent("compare_size_ms-ssim.png")
        let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, graphImg, nil)
        CGImageDestinationFinalize(dest)
        print("Saved: \(fileURL.path)")
    } else {
        print("Failed to generate quality graph image.")
    }
    
    // --- Draw Speed Graph (Time vs MS-SSIM) ---
    
    print("\nGenerating Speed Graph...")
    if let speedGraphImg = drawSpeedGraph(title: "Speed Comparison: JPEG vs veif", jpegPoints: jpegPoints, veifPoints: veifPoints) {
        let fileURL = outURL.appendingPathComponent("compare_speed_ms-ssim.png")
        let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, speedGraphImg, nil)
        CGImageDestinationFinalize(dest)
        print("Saved: \(fileURL.path)")
    } else {
        print("Failed to generate speed graph image.")
    }

    // --- Draw Thumbnail Speed Graph (Total: Orig + Thumb) ---
    
    print("\nGenerating Thumbnail Speed Graph...")
    if let thumbGraphImg = drawThumbnailSpeedGraph(
        title: "Speed Comparison: JPEG vs veif (Thumbnail)",
        jpegPoints: jpegPoints,
        jpegThumbPoints: jpegThumbPoints,
        veifPoints: veifThumbPoints
    ) {
        let fileURL = outURL.appendingPathComponent("compare_total_thumbnail_ms-ssim.png")
        let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, thumbGraphImg, nil)
        CGImageDestinationFinalize(dest)
        print("Saved: \(fileURL.path)")
    } else {
         print("Failed to generate thumbnail speed graph image.")
    }
    
    // --- Resolution Quality Graph (Size vs MS-SSIM) ---
    // 160x120, 320x240, 640x480, 1280x960, 2560x1920
    
    print("\n=== Resolution Quality Collection ===")
    
    let resolutions: [(Int, Int, Int, Int)] = [
        (160, 120, 20, 200),       // 160x120, range 20-200k, step 20
        (320, 240, 20, 200),       // 320x240, range 20-200k, step 20
        (640, 480, 50, 400),       // 640x480, range 50-400k, step 50
        (1280, 960, 50, 400),    // 1280x960, range 50-400k, step 50
    ]
    
    // Store results: [ResolutionString: (JPEGPoints, veifPoints)]
    var resolutionResults: [String: ([(Double, Double)], [(Double, Double)])] = [:]
    
    // Pre-calculate source CGImage for resizing
    guard let srcCGImage = yCbCrToCGImage(img: originImg) else {
        fatalError("Failed to convert source to CGImage for resizing")
    }
    
    for (w, h, minRate, maxRate) in resolutions {
        print("\n--- Resolution: \(w)x\(h) ---")
        let resString = "\(w)x\(h)"
        
        // 1. Resize Source to Target Resolution (Ground Truth for this resolution)
        guard let resized = resizeCGImage(image: srcCGImage, width: w, height: h) else {
            print("Failed to resize to \(w)x\(h)")
            continue
        }
        // Convert back to YCbCr for processing (as our helpers take YCbCrImage)
        guard let resOriginImg = try? cgImageToYCbCr(image: resized) else {
             print("Failed to convert resized image back to YCbCr")
             continue
        }
        
        // 2. JPEG Collection
        var jPoints: [(Double, Double)] = []
        for q in stride(from: 10, through: 100, by: 10) {
            // Re-use runJPEGSinglePoint logic but with resized image
            // Note: runJPEGSinglePoint returns (SizeKB, MS-SSIM, EncTime, DecTime). We only need Size/SSIM.
            if let p = runJPEGSinglePoint(q: q, originImg: resOriginImg) {
                jPoints.append((p.0, p.1))
                print(String(format: "JPEG Q=%3d Size=%6.2fKB SSIM=%.4f", q, p.0, p.1))
            }
        }
        
        // 3. veif Collection
        var vPoints: [(Double, Double)] = []
        let step = (maxRate - minRate) / 10 // roughly 10 steps
        let actualStep = max(10, step)
        
        for bitrate in stride(from: minRate, through: maxRate, by: actualStep) {
            if let p = await runVeifSinglePoint(bitrate: bitrate, originImg: resOriginImg) {
                vPoints.append((p.0, p.1))
                print(String(format: "veif Rate=%4dk Size=%6.2fKB SSIM=%.4f", bitrate, p.0, p.1))
            }
        }
        
        resolutionResults[resString] = (jPoints, vPoints)
    }
    
    // Draw Graph
    print("\nGenerating Resolution Quality Graph...")
    // Prepare data for drawing: Map to struct or tuple that holds label + points
    var drawData: [(String, [(Double, Double)], [(Double, Double)])] = []
    
    // Preserve order
    for (w, h, _, _) in resolutions {
        let key = "\(w)x\(h)"
        if let pair = resolutionResults[key] {
            drawData.append((key, pair.0, pair.1))
        }
    }
    
    if let graphImg = drawResolutionQualityGraph(title: "Quality Comparison across Resolutions", data: drawData) {
        let fileURL = outURL.appendingPathComponent("compare_resolution_quality_ms-ssim.png")
        let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, graphImg, nil)
        CGImageDestinationFinalize(dest)
        print("Saved: \(fileURL.path)")
    } else {
        print("Failed to generate resolution quality graph image.")
    }
}


// MARK: - Data Collection Helpers

// Returns: (SizeKB, MS-SSIM, EncTimeMS, DecTimeMS)
func runJPEGSinglePoint(q: Int, originImg: YCbCrImage) -> (Double, Double, Double, Double)? {
    guard let cgImage = yCbCrToCGImage(img: originImg) else { return nil }
    
    // 1. Warmup & Base Encode for Size/Quality
    let baseDstData = NSMutableData()
    guard let baseDest = CGImageDestinationCreateWithData(baseDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    let options = [kCGImageDestinationLossyCompressionQuality: (Double(q) / 100.0)] as CFDictionary
    CGImageDestinationAddImage(baseDest, cgImage, options)
    if !CGImageDestinationFinalize(baseDest) { return nil }
    
    let baseEncodedBytes = baseDstData as Data
    guard let baseDecodedYCbCr = try? pngToYCbCr(data: baseEncodedBytes) else { return nil }
    
    let metrics = calcMetrics(ref: originImg, target: baseDecodedYCbCr)
    let sizeKB = (Double(baseEncodedBytes.count) / 1024.0)
    
    // 2. Measure Encode Time (100 times, median)
    var encTimes: [Double] = []
    let iterations = 100
    
    for _ in 0..<iterations {
        let dstData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(dstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
        
        let start = CFAbsoluteTimeGetCurrent()
        CGImageDestinationAddImage(dest, cgImage, options)
        CGImageDestinationFinalize(dest)
        let dur = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        encTimes.append(dur)
    }
    let encTime = mean(encTimes)
    
    // 3. Measure Decode Time (100 times, drop first, mean)
    var decTimes: [Double] = []
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? pngToYCbCr(data: baseEncodedBytes)
        let dur = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        decTimes.append(dur)
    }
    let decTime = mean(decTimes)
    
    return (sizeKB, metrics.msssim, encTime, decTime)
}

func runVeifSinglePoint(bitrate: Int, originImg: YCbCrImage) async -> (Double, Double, Double, Double)? {
    // veif uses maxbitrate in bits
    let targetBits = (bitrate * 1000)
    
    // 1. Warmup & Base Encode
    guard let out = try? await encodeOne(img: originImg, maxbitrate: targetBits) else { return nil }
    guard let dec = try? await decodeOne(r: out) else { return nil }
    
    let metrics = calcMetrics(ref: originImg, target: dec)
    let sizeKB = (Double(out.count) / 1024.0)
    
    let iterations = 100
    
    // 2. Measure Encode Time
    var encTimes: [Double] = []
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? await encodeOne(img: originImg, maxbitrate: targetBits)
        let dur = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        encTimes.append(dur)
    }
    let encTime = mean(encTimes)
    
    // 3. Measure Decode Time
    var decTimes: [Double] = []
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? await decodeOne(r: out)
        let dur = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        decTimes.append(dur)
    }
    let decTime = mean(decTimes)
    
    return (sizeKB, metrics.msssim, encTime, decTime)
}

func mean(_ values: [Double]) -> Double {
    let validValues = values.dropFirst().sorted{ $0 < $1 }.dropLast(10)
    if validValues.isEmpty { return 0 }
    return validValues.reduce(0, +) / Double(validValues.count)
}

// MARK: - Graph Drawing

func drawComparisonGraph(title: String, jpegPoints: [(Double, Double)], veifPoints: [(Double, Double)]) -> CGImage? {
    let width = 1200
    let height = 800
    let padding = 60.0
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    
    // Background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // Graph Area
    let graphRect = CGRect(x: padding, y: padding, width: Double(width) - (padding * 2), height: Double(height) - (padding * 2))
    
    // Determine Ranges
    let allPoints = jpegPoints + veifPoints
    let minX = 0.0
    let maxX = (allPoints.map { $0.0 }.max() ?? 100.0) * 1.1 // Add 10% padding
    let minY = 0.8 // Fixed range for MS-SSIM usually high
    let maxY = 1.0
    
    // Helper to map coordinate
    func mapPoint(_ p: (Double, Double)) -> CGPoint {
        let x = graphRect.minX + ((p.0 - minX) / (maxX - minX)) * graphRect.width
        let y = graphRect.minY + ((p.1 - minY) / (maxY - minY)) * graphRect.height
        return CGPoint(x: x, y: y)
    }
    
    // Draw Grid & Axes
    context.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
    context.setLineWidth(1.0)
    
    // Vertical Grid (Size)
    let gridCountX = 10
    for i in 0...gridCountX {
        let val = minX + (maxX - minX) * (Double(i) / Double(gridCountX))
        let x = graphRect.minX + (Double(i) / Double(gridCountX)) * graphRect.width
        context.move(to: CGPoint(x: x, y: graphRect.minY))
        context.addLine(to: CGPoint(x: x, y: graphRect.maxY))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.0fKB", val), x: x, y: graphRect.minY - 15, context: context, alignCenter: true)
    }
    
    // Horizontal Grid (MS-SSIM)
    let gridCountY = 10
    for i in 0...gridCountY {
        let val = minY + (maxY - minY) * (Double(i) / Double(gridCountY))
        let y = graphRect.minY + (Double(i) / Double(gridCountY)) * graphRect.height
        context.move(to: CGPoint(x: graphRect.minX, y: y))
        context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.2f", val), x: graphRect.minX - 25, y: y - 5, context: context, alignCenter: false)
    }
    
    // Draw Plot Lines
    
    // JPEG (Red)
    if !jpegPoints.isEmpty {
        context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.8))
        context.setLineWidth(2.0)
        context.beginPath()
        let sorted = jpegPoints.sorted { $0.0 < $1.0 }
        if let first = sorted.first {
            let pt = mapPoint(first)
            context.move(to: pt)
            for p in sorted.dropFirst() {
                context.addLine(to: mapPoint(p))
            }
        }
        context.strokePath()
        
        // Dots
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        for p in sorted {
            let pt = mapPoint(p)
            context.fillEllipse(in: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
        }
    }
    
    // veif (Blue)
    if !veifPoints.isEmpty {
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.8))
        context.setLineWidth(2.0)
        context.beginPath()
        let sorted = veifPoints.sorted { $0.0 < $1.0 }
        if let first = sorted.first {
            let pt = mapPoint(first)
            context.move(to: pt)
            for p in sorted.dropFirst() {
                context.addLine(to: mapPoint(p))
            }
        }
        context.strokePath()
        
        // Dots
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        for p in sorted {
            let pt = mapPoint(p)
            context.fillEllipse(in: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
        }
    }
    
    // Legend
    let legendRect = CGRect(x: graphRect.maxX - 150, y: graphRect.minY + 20, width: 130, height: 60)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    context.fill(legendRect)
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(1.0)
    context.stroke(legendRect)
    
    // Legend Item 1 (JPEG)
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fillEllipse(in: CGRect(x: legendRect.minX + 10, y: legendRect.minY + 15, width: 8, height: 8))
    drawText(text: "JPEG", x: legendRect.minX + 25, y: legendRect.minY + 10, context: context, alignCenter: false)
    
    // Legend Item 2 (veif)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: legendRect.minX + 10, y: legendRect.minY + 35, width: 8, height: 8))
    drawText(text: "veif", x: legendRect.minX + 25, y: legendRect.minY + 30, context: context, alignCenter: false)
    
    // Axis Titles
    // X-Axis
    drawText(text: "File Size (KB)", x: Double(width) / 2.0, y: 15, context: context, alignCenter: true, fontSize: 16)
    // Y-Axis (Rotated)
    drawRotatedText(text: "MS-SSIM", x: 15, y: Double(height) / 2.0, angle: .pi / 2, context: context, fontSize: 16)
    
    // Main Title
    drawText(text: title, x: Double(width) / 2.0, y: Double(height) - 40, context: context, alignCenter: true, fontSize: 24)
    
    return context.makeImage()
}

func drawSpeedGraph(title: String, jpegPoints: [(Double, Double, Double, Double)], veifPoints: [(Double, Double, Double, Double)]) -> CGImage? {
    let width = 1200
    let height = 800
    let padding = 60.0
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    
    // Background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // Graph Area
    // Increase left padding for Y-axis title
    let leftPadding = 80.0
    let graphRect = CGRect(x: leftPadding, y: padding, width: Double(width) - (leftPadding + padding), height: Double(height) - (padding * 2))
    
    // Determine Ranges
    // X: Time (ms) - EncTime and DecTime from both sets
    let jpegEncTimes = jpegPoints.map { $0.2 }
    let jpegDecTimes = jpegPoints.map { $0.3 }
    let veifEncTimes = veifPoints.map { $0.2 }
    let veifDecTimes = veifPoints.map { $0.3 }
    let allTimes = jpegEncTimes + jpegDecTimes + veifEncTimes + veifDecTimes
    
    let minX = 0.0
    let maxX = (allTimes.max() ?? 10.0) * 1.1
    let minY = 0.8
    let maxY = 1.0
    
    // Helper to map coordinate
    func mapPoint(time: Double, msssim: Double) -> CGPoint {
        let x = graphRect.minX + ((time - minX) / (maxX - minX)) * graphRect.width
        let y = graphRect.minY + ((msssim - minY) / (maxY - minY)) * graphRect.height
        return CGPoint(x: x, y: y)
    }
    
    // Draw Grid & Axes
    context.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
    context.setLineWidth(1.0)
    
    // Vertical Grid (Time ms)
    let gridCountX = 10
    for i in 0...gridCountX {
        let val = minX + (maxX - minX) * (Double(i) / Double(gridCountX))
        let x = graphRect.minX + (Double(i) / Double(gridCountX)) * graphRect.width
        context.move(to: CGPoint(x: x, y: graphRect.minY))
        context.addLine(to: CGPoint(x: x, y: graphRect.maxY))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.1fms", val), x: x, y: graphRect.minY - 15, context: context, alignCenter: true)
    }
    
    // Horizontal Grid (MS-SSIM)
    let gridCountY = 10
    for i in 0...gridCountY {
        let val = minY + (maxY - minY) * (Double(i) / Double(gridCountY))
        let y = graphRect.minY + (Double(i) / Double(gridCountY)) * graphRect.height
        context.move(to: CGPoint(x: graphRect.minX, y: y))
        context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.2f", val), x: graphRect.minX - 35, y: y - 5, context: context, alignCenter: false)
    }
    
    // Draw Lines helper
    func drawLine(points: [(Double, Double, Double, Double)], timeIndex: Int, r: CGFloat, g: CGFloat, b: CGFloat) {
        if points.isEmpty { return }
        context.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 0.8))
        context.setLineWidth(2.0)
        context.beginPath()
        
        // timeIndex: 2 for Enc, 3 for Dec
        let sorted = points.sorted { (timeIndex == 2 ? $0.2 : $0.3) < (timeIndex == 2 ? $1.2 : $1.3) }
        
        if let first = sorted.first {
            let t = (timeIndex == 2 ? first.2 : first.3)
            let pt = mapPoint(time: t, msssim: first.1)
            context.move(to: pt)
            for p in sorted.dropFirst() {
                let t = (timeIndex == 2 ? p.2 : p.3)
                context.addLine(to: mapPoint(time: t, msssim: p.1))
            }
        }
        context.strokePath()
        
        // Dots
        context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        for p in sorted {
            let t = (timeIndex == 2 ? p.2 : p.3)
            let pt = mapPoint(time: t, msssim: p.1)
            context.fillEllipse(in: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
        }
    }
    
    // 1. JPEG Encode (Red)
    drawLine(points: jpegPoints, timeIndex: 2, r: 1, g: 0, b: 0)
    
    // 2. JPEG Decode (Orange)
    drawLine(points: jpegPoints, timeIndex: 3, r: 1, g: 0.5, b: 0)
    
    // 3. veif Encode (Blue)
    drawLine(points: veifPoints, timeIndex: 2, r: 0, g: 0, b: 1)
    
    // 4. veif Decode (Cyan)
    drawLine(points: veifPoints, timeIndex: 3, r: 0, g: 0.8, b: 0.8)
    
    // Legend
    let legendRect = CGRect(x: graphRect.maxX - 160, y: graphRect.minY + 20, width: 140, height: 100)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    context.fill(legendRect)
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(1.0)
    context.stroke(legendRect)
    
    func drawLegendItem(label: String, r: CGFloat, g: CGFloat, b: CGFloat, index: Int) {
        let y = legendRect.minY + 15 + Double(index * 20)
        context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        context.fillEllipse(in: CGRect(x: legendRect.minX + 10, y: y, width: 8, height: 8))
        drawText(text: label, x: legendRect.minX + 25, y: y - 5, context: context, alignCenter: false)
    }
    
    drawLegendItem(label: "JPEG Enc", r: 1, g: 0, b: 0, index: 0)
    drawLegendItem(label: "JPEG Dec", r: 1, g: 0.5, b: 0, index: 1)
    drawLegendItem(label: "veif Enc", r: 0, g: 0, b: 1, index: 2)
    drawLegendItem(label: "veif Dec", r: 0, g: 0.8, b: 0.8, index: 3)
    
    // Axis Titles
    // X-Axis
    drawText(text: "Time (ms)", x: Double(width) / 2.0, y: 15, context: context, alignCenter: true, fontSize: 16)
    // Y-Axis (Rotated)
    drawRotatedText(text: "MS-SSIM", x: 15, y: Double(height) / 2.0, angle: .pi / 2, context: context, fontSize: 16)
    
    // Main Title
    drawText(text: title, x: Double(width) / 2.0, y: Double(height) - 40, context: context, alignCenter: true, fontSize: 24)
    
    return context.makeImage()
}

#if canImport(CoreText)
import CoreText
#endif

func drawRotatedText(text: String, x: Double, y: Double, angle: CGFloat, context: CGContext, fontSize: CGFloat = 12) {
    #if canImport(CoreText)
    context.saveGState()
    context.translateBy(x: x, y: y)
    context.rotate(by: angle)
    
    // Draw at specific origin relative to rotated context
    drawText(text: text, x: 0, y: 0, context: context, alignCenter: true, fontSize: fontSize)
    
    context.restoreGState()
    #endif
}

func drawText(text: String, x: Double, y: Double, context: CGContext, alignCenter: Bool, fontSize: CGFloat = 12) {
    #if canImport(CoreText)
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ]
    let attrStr = NSAttributedString(string: text, attributes: attributes)
    
    let line = CTLineCreateWithAttributedString(attrStr)
    context.saveGState()
    context.textMatrix = .identity
    
    var posX = x
    if alignCenter {
        let bounds = CTLineGetImageBounds(line, context)
        posX -= (bounds.width / 2.0)
    }
    
    context.textPosition = CGPoint(x: posX, y: y)
    CTLineDraw(line, context)
    context.restoreGState()
    #else
    print("CoreText not available, skipping text: \(text)")
    #endif
}

// MARK: - Thumbnail Helpers & Functions

func getLayer0Size(data: Data) -> Int {
    // veif format:
    // [layer0_len:4][layer0_data][layer1_len:4][layer1_data]...
    if data.count < 4 { return 0 }
    let len = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    return 4 + Int(len)
}

func resizeCGImage(image: CGImage, scale: CGFloat) -> CGImage? {
    let newWidth = Int(Double(image.width) * scale)
    let newHeight = Int(Double(image.height) * scale)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    return context.makeImage()
}

// Returns: (ThumbSizeKB, ThumbSSIM, ThumbEncTime, ThumbDecTime)
func runJPEGThumbnailSinglePoint(q: Int, originImg: YCbCrImage) -> (Double, Double, Double, Double)? {
    guard let cgImage = yCbCrToCGImage(img: originImg) else { return nil }
    
    // 1. Prepare Source JPEG (Simulate Server File)
    let srcDstData = NSMutableData()
    guard let srcDest = CGImageDestinationCreateWithData(srcDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    let srcOptions = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary // High Quality Source
    CGImageDestinationAddImage(srcDest, cgImage, srcOptions)
    if !CGImageDestinationFinalize(srcDest) { return nil }
    let srcJpegData = srcDstData as Data
    
    // 2. Resize (1/4) for Metrics
    guard let resizedCGImage = resizeCGImage(image: cgImage, scale: 0.25) else { return nil }
    
    // 3. Encode Thumbnail (for Size/Metrics)
    let thumbDstData = NSMutableData()
    guard let thumbDest = CGImageDestinationCreateWithData(thumbDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    let options = [kCGImageDestinationLossyCompressionQuality: (Double(q) / 100.0)] as CFDictionary
    CGImageDestinationAddImage(thumbDest, resizedCGImage, options)
    if !CGImageDestinationFinalize(thumbDest) { return nil }
    
    let thumbEncodedBytes = thumbDstData as Data
    let thumbSizeKB = (Double(thumbEncodedBytes.count) / 1024.0)
    
    // 4. Decode Thumbnail for Metrics
    guard let thumbDecodedYCbCr = try? pngToYCbCr(data: thumbEncodedBytes) else { return nil }
    
    // Metric Ref: Resize original 1/4 (twice halfNN to get 1/4)
    let refThumb = resizeHalfNN(resizeHalfNN(originImg))
    let thumbMetrics = calcMetrics(ref: refThumb, target: thumbDecodedYCbCr)
    
    let iterations = 100
    var encTimes: [Double] = []
    
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        // A. Full Decode
        if let sourceDataProvider = CGDataProvider(data: srcJpegData as CFData),
           let sourceImage = CGImage(jpegDataProviderSource: sourceDataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            // B. Resize
            if let r = resizeCGImage(image: sourceImage, scale: 0.25) {
                // C. Thumb Encode
                let loopDstData = NSMutableData()
                if let loopDest = CGImageDestinationCreateWithData(loopDstData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(loopDest, r, options)
                    CGImageDestinationFinalize(loopDest)
                }
            }
        }
        encTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
    }
    
    var decTimes: [Double] = []
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? pngToYCbCr(data: thumbEncodedBytes)
        decTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
    }
    
    let encTime = mean(encTimes)
    let decTime = mean(decTimes)
    
    return (thumbSizeKB, thumbMetrics.msssim, encTime, decTime)
}

func cgImageToYCbCr(image: CGImage) throws -> YCbCrImage {
    let width = image.width
    let height = image.height
    
    // Create a context to draw the image into a canonical format (RGBA 8-bit)
    // This avoids issues with different source formats or strides.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8
    
    // Allocate buffer for raw pixel data
    var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
    
    guard let context = CGContext(data: &rawData,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
        throw NSError(domain: "veif", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
    }
    
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    // RGB to YCbCr conversion (BT.601)
    let chromaWidth = (width + 1) / 2
    let chromaHeight = (height + 1) / 2
    
    var yPlane = [UInt8](repeating: 0, count: width * height)
    var cbPlane = [UInt8](repeating: 0, count: chromaWidth * chromaHeight)
    var crPlane = [UInt8](repeating: 0, count: chromaWidth * chromaHeight)
    
    for row in 0..<height {
        for col in 0..<width {
            let pixelIndex = (row * bytesPerRow) + (col * bytesPerPixel)
            
            // Safety check for index bound
            if pixelIndex + 2 >= rawData.count { continue }
            
            let r = Double(rawData[pixelIndex])
            let g = Double(rawData[pixelIndex + 1])
            let b = Double(rawData[pixelIndex + 2])
            
            let y = 0.299 * r + 0.587 * g + 0.114 * b
            let yIdx = row * width + col
            if yIdx < yPlane.count {
                 yPlane[yIdx] = UInt8(clamping: Int(y))
            }
            
            if row % 2 == 0 && col % 2 == 0 {
                let cb = -0.1687 * r - 0.3313 * g + 0.5 * b + 128.0
                let cr = 0.5 * r - 0.4187 * g - 0.0813 * b + 128.0
                
                let chromaIndex = (row / 2) * chromaWidth + (col / 2)
                if chromaIndex < cbPlane.count {
                    cbPlane[chromaIndex] = UInt8(clamping: Int(cb))
                    crPlane[chromaIndex] = UInt8(clamping: Int(cr))
                }
            }
        }
    }
    
    var img = YCbCrImage(width: width, height: height, ratio: .ratio420) // Use 420 as default since loop does subsampling
    img.yPlane = yPlane
    img.cbPlane = cbPlane
    img.crPlane = crPlane
    
    return img
}

func resizeCGImage(image: CGImage, width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

func drawResolutionQualityGraph(title: String, data: [(String, [(Double, Double)], [(Double, Double)])]) -> CGImage? {
    // data: [(ResolutionString, jpegPoints, veifPoints)]
    let width = 1200
    let height = 800
    let padding = 60.0
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    
    // Background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // Graph Area
    // Increase left padding for Y-axis title
    let leftPadding = 80.0
    let graphRect = CGRect(x: leftPadding, y: padding, width: Double(width) - (leftPadding + padding), height: Double(height) - (padding * 2))
    
    // Determine Ranges
    var allSizeKBs: [Double] = []
    
    for (_, jPoints, vPoints) in data {
        allSizeKBs.append(contentsOf: jPoints.map { $0.0 })
        allSizeKBs.append(contentsOf: vPoints.map { $0.0 })
    }
    
    let minX = 0.0
    let maxX = (allSizeKBs.max() ?? 100.0) * 1.1
    let minY = 0.8
    let maxY = 1.0
    
    // Helper to map coordinate
    func mapPoint(sizeKB: Double, msssim: Double) -> CGPoint {
        let x = graphRect.minX + ((sizeKB - minX) / (maxX - minX)) * graphRect.width
        let y = graphRect.minY + ((msssim - minY) / (maxY - minY)) * graphRect.height
        return CGPoint(x: x, y: y)
    }
    
    // Draw Grid & Axes
    context.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
    context.setLineWidth(1.0)
    
    // Vertical Grid (Size KB)
    let gridCountX = 10
    for i in 0...gridCountX {
        let val = minX + (maxX - minX) * (Double(i) / Double(gridCountX))
        let x = graphRect.minX + (Double(i) / Double(gridCountX)) * graphRect.width
        context.move(to: CGPoint(x: x, y: graphRect.minY))
        context.addLine(to: CGPoint(x: x, y: graphRect.maxY))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.0fKB", val), x: x, y: graphRect.minY - 15, context: context, alignCenter: true)
    }
    
    // Horizontal Grid (MS-SSIM)
    let gridCountY = 10
    for i in 0...gridCountY {
        let val = minY + (maxY - minY) * (Double(i) / Double(gridCountY))
        let y = graphRect.minY + (Double(i) / Double(gridCountY)) * graphRect.height
        context.move(to: CGPoint(x: graphRect.minX, y: y))
        context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.2f", val), x: graphRect.minX - 35, y: y - 5, context: context, alignCenter: false)
    }
    
    // Draw Lines
    for (label, jPoints, vPoints) in data {
        // JPEG: Red
        if !jPoints.isEmpty {
            let sorted = jPoints.sorted { $0.0 < $1.0 }
            
            context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.6))
            context.setLineWidth(2.0)
            context.beginPath()
            if let first = sorted.first {
                context.move(to: mapPoint(sizeKB: first.0, msssim: first.1))
                for p in sorted.dropFirst() {
                    context.addLine(to: mapPoint(sizeKB: p.0, msssim: p.1))
                }
            }
            context.strokePath()
            
            // Label at the end
            if let last = sorted.last {
                let pt = mapPoint(sizeKB: last.0, msssim: last.1)
                drawText(text: label, x: pt.x + 5, y: pt.y - 5, context: context, alignCenter: false, fontSize: 10)
            }
        }
        
        // veif: Blue
        if !vPoints.isEmpty {
            let sorted = vPoints.sorted { $0.0 < $1.0 }
            
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.6))
            context.setLineWidth(2.0)
            context.beginPath()
            if let first = sorted.first {
                context.move(to: mapPoint(sizeKB: first.0, msssim: first.1))
                for p in sorted.dropFirst() {
                    context.addLine(to: mapPoint(sizeKB: p.0, msssim: p.1))
                }
            }
            context.strokePath()
            
            // Label at the end (for veif too, though might overlap with JPEG if close)
            if let last = sorted.last {
                let pt = mapPoint(sizeKB: last.0, msssim: last.1)
                 // Offset slightly differently for veif to avoid overlap if similar
                drawText(text: label, x: pt.x + 5, y: pt.y + 5, context: context, alignCenter: false, fontSize: 10)
            }
        }
    }
    
    // Legend
    let legendRect = CGRect(x: graphRect.maxX - 150, y: graphRect.minY + 20, width: 130, height: 60)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    context.fill(legendRect)
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(1.0)
    context.stroke(legendRect)
    
    // Item 1: JPEG (Red)
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fillEllipse(in: CGRect(x: legendRect.minX + 10, y: legendRect.minY + 15, width: 8, height: 8))
    drawText(text: "JPEG", x: legendRect.minX + 25, y: legendRect.minY + 10, context: context, alignCenter: false)
    
    // Item 2: veif (Blue)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: legendRect.minX + 10, y: legendRect.minY + 35, width: 8, height: 8))
    drawText(text: "veif", x: legendRect.minX + 25, y: legendRect.minY + 30, context: context, alignCenter: false)


    // Axis Titles
    drawText(text: "File Size (KB)", x: Double(width) / 2.0, y: 15, context: context, alignCenter: true, fontSize: 16)
    drawRotatedText(text: "MS-SSIM", x: 15, y: Double(height) / 2.0, angle: .pi / 2, context: context, fontSize: 16)
    
    drawText(text: title, x: Double(width) / 2.0, y: Double(height) - 40, context: context, alignCenter: true, fontSize: 24)
    
    return context.makeImage()
}

// Returns: (ThumbSizeKB, ThumbSSIM, EncTime(Full), ThumbDecTime)
func runVeifThumbnailSinglePoint(bitrate: Int, originImg: YCbCrImage) async -> (Double, Double, Double, Double)? {
    let targetBits = (bitrate * 1000)
    
    // 1. Encode Full (Standard) to get Multi-Resolution binary
    // Use `encode` (not encodeOne)
    guard let out = try? await encode(img: originImg, maxbitrate: targetBits) else { return nil }
    
    // 2. Thumbnail Metrics (Layer0)
    // Decode only Layer0 to check metrics
    guard let (l0, _, _) = try? await decode(r: out) else { return nil }
    
    let layer0Size = getLayer0Size(data: out)
    let thumbSizeKB = (Double(layer0Size) / 1024.0)
    
    let refThumb = resizeHalfNN(resizeHalfNN(originImg))
    let thumbMetrics = calcMetrics(ref: refThumb, target: l0)
    
    // 3. Measure Enc/Dec Time
    // Enc Time: Full Encode (Generation Cost) - Though for verification, we plot is as Enc Time, 
    // but in Total Comparison, we will treat it as 0 (pre-encoded).
    // Thumb Dec Time: decodeLayer0 Cost
    
    let iterations = 100
    var encTimes: [Double] = []
    
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? await encode(img: originImg, maxbitrate: targetBits)
        encTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
    }
    
    var thumbDecTimes: [Double] = []
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = try? await decodeLayer0(r: out)
        thumbDecTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
    }
    
    let encTime = mean(encTimes)
    let decTime = mean(thumbDecTimes)
    
    return (thumbSizeKB, thumbMetrics.msssim, encTime, decTime)
}

func drawThumbnailSpeedGraph(title: String, 
                             jpegPoints: [(Double, Double, Double, Double)], 
                             jpegThumbPoints: [(Double, Double, Double, Double)],
                             veifPoints: [(Double, Double, Double, Double)]) -> CGImage? {
    let width = 1200
    let height = 800
    let padding = 60.0
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    
    // Background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // Graph Area
    // Increase left padding for Y-axis title
    let leftPadding = 80.0
    let graphRect = CGRect(x: leftPadding, y: padding, width: Double(width) - (leftPadding + padding), height: Double(height) - (padding * 2))
    
    // Calculate Total Times for Range Determination
    // JPEG Total: Enc(Gen) + Dec(View)
    let jpegThumbTotalTimes = jpegThumbPoints.map { $0.2 + $0.3 }
    // veif Total: Dec(View) ONLY (Enc is pre-calculated/stored)
    let veifTotalTimes = veifPoints.map { $0.3 }
    
    // Determine Ranges
    // X: Time (ms) - EncTime, DecTime, and TotalTime from all relevant sets
    let allTimes = jpegPoints.map { $0.2 } + jpegPoints.map { $0.3 } +
                   jpegThumbPoints.map { $0.2 } + jpegThumbPoints.map { $0.3 } +
                   veifPoints.map { $0.2 } + veifPoints.map { $0.3 } +
                   jpegThumbTotalTimes + veifTotalTimes
    
    let minX = 0.0
    let maxX = (allTimes.max() ?? 10.0) * 1.1
    let minY = 0.8
    let maxY = 1.0
    
    // Helper to map coordinate
    func mapPoint(time: Double, msssim: Double) -> CGPoint {
        let x = graphRect.minX + ((time - minX) / (maxX - minX)) * graphRect.width
        let y = graphRect.minY + ((msssim - minY) / (maxY - minY)) * graphRect.height
        return CGPoint(x: x, y: y)
    }
    
    // Draw Grid & Axes
    context.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
    context.setLineWidth(1.0)
    
    // Vertical Grid (Time ms)
    let gridCountX = 10
    for i in 0...gridCountX {
        let val = minX + (maxX - minX) * (Double(i) / Double(gridCountX))
        let x = graphRect.minX + (Double(i) / Double(gridCountX)) * graphRect.width
        context.move(to: CGPoint(x: x, y: graphRect.minY))
        context.addLine(to: CGPoint(x: x, y: graphRect.maxY))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.1fms", val), x: x, y: graphRect.minY - 15, context: context, alignCenter: true)
    }
    
    // Horizontal Grid (MS-SSIM)
    let gridCountY = 10
    for i in 0...gridCountY {
        let val = minY + (maxY - minY) * (Double(i) / Double(gridCountY))
        let y = graphRect.minY + (Double(i) / Double(gridCountY)) * graphRect.height
        context.move(to: CGPoint(x: graphRect.minX, y: y))
        context.addLine(to: CGPoint(x: graphRect.maxX, y: y))
        context.strokePath()
        
        // Label
        drawText(text: String(format: "%.2f", val), x: graphRect.minX - 35, y: y - 5, context: context, alignCenter: false)
    }
    
    // Draw Lines helper
    func drawLine(points: [(Double, Double, Double, Double)], timeIndex: Int, r: CGFloat, g: CGFloat, b: CGFloat, dashed: Bool = false, lineWidth: CGFloat = 2.0) {
        if points.isEmpty { return }
        context.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 0.8))
        context.setLineWidth(lineWidth)
        if dashed {
            context.setLineDash(phase: 0, lengths: [5, 5])
        } else {
            context.setLineDash(phase: 0, lengths: [])
        }
        
        context.beginPath()
        
        // timeIndex: 2 for Enc, 3 for Dec. For Total, we assume caller prepared data in index 2 (or 3).
        let sorted = points.sorted { (timeIndex == 2 ? $0.2 : $0.3) < (timeIndex == 2 ? $1.2 : $1.3) }
        
        if let first = sorted.first {
            let t = (timeIndex == 2 ? first.2 : first.3)
            let pt = mapPoint(time: t, msssim: first.1)
            context.move(to: pt)
            for p in sorted.dropFirst() {
                let t = (timeIndex == 2 ? p.2 : p.3)
                context.addLine(to: mapPoint(time: t, msssim: p.1))
            }
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: []) // Reset dash
        
        // Dots
        if dashed {
            context.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.setLineWidth(1.5)
            for p in sorted {
                let t = (timeIndex == 2 ? p.2 : p.3)
                let pt = mapPoint(time: t, msssim: p.1)
                context.strokeEllipse(in: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
            }
        } else {
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            for p in sorted {
                let t = (timeIndex == 2 ? p.2 : p.3)
                let pt = mapPoint(time: t, msssim: p.1)
                context.fillEllipse(in: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
            }
        }
    }
    
    // 1. JPEG Enc (Thin Red)
    drawLine(points: jpegPoints, timeIndex: 2, r: 1, g: 0.8, b: 0.8, lineWidth: 1.0)
    // 2. JPEG Dec (Thin Orange)
    drawLine(points: jpegPoints, timeIndex: 3, r: 1, g: 0.9, b: 0.8, lineWidth: 1.0)
    
    // 3. veif Enc (Thin Blue - actually Full Enc)
    drawLine(points: veifPoints, timeIndex: 2, r: 0.8, g: 0.8, b: 1, lineWidth: 1.0)
    // 4. veif Dec (Thin Cyan - actually Layer0 Dec)
    drawLine(points: veifPoints, timeIndex: 3, r: 0.8, g: 1, b: 1, lineWidth: 1.0)
    
    // 5. JPEG Thumb Enc (Red Dashed)
    drawLine(points: jpegThumbPoints, timeIndex: 2, r: 1, g: 0, b: 0, dashed: true)
    // 6. JPEG Thumb Dec (Orange Dashed)
    drawLine(points: jpegThumbPoints, timeIndex: 3, r: 1, g: 0.5, b: 0, dashed: true)
    
    // --- TOTAL LINES (Thick) ---
    
    // 7. JPEG Thumb Total (Purple)
    // Enc(Gen) + Dec(View)
    let jpegThumbTotalPoints = jpegThumbPoints.map { ($0.0, $0.1, $0.2 + $0.3, 0.0) }
    drawLine(points: jpegThumbTotalPoints, timeIndex: 2, r: 0.5, g: 0, b: 0.5, lineWidth: 3.0)
    
    // 8. veif Thumb Total (Green)
    // Dec(View) ONLY, Enc is 0
    let veifTotalPoints = veifPoints.map { ($0.0, $0.1, $0.3, 0.0) }
    drawLine(points: veifTotalPoints, timeIndex: 2, r: 0, g: 0.5, b: 0, lineWidth: 3.0)
        
    // Legend
    let legendRect = CGRect(x: graphRect.maxX - 180, y: graphRect.minY + 20, width: 160, height: 180)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.fill(legendRect)
    context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.setLineWidth(1.0)
    context.stroke(legendRect)
    
    func drawLegendItem(label: String, r: CGFloat, g: CGFloat, b: CGFloat, index: Int, dashed: Bool, bold: Bool = false) {
        let y = legendRect.minY + 15 + Double(index * 20)
        
        let pointSize = bold ? 10.0 : 8.0
        
        if dashed {
             context.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 1))
             context.setLineWidth(1.5)
             context.strokeEllipse(in: CGRect(x: legendRect.minX + 10, y: y, width: pointSize, height: pointSize))
        } else {
             context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
             context.fillEllipse(in: CGRect(x: legendRect.minX + 10, y: y, width: pointSize, height: pointSize))
        }
        drawText(text: label, x: legendRect.minX + 25, y: y - 5, context: context, alignCenter: false, fontSize: bold ? 13 : 11)
    }
    
    drawLegendItem(label: "JPEG Orig Enc", r: 1, g: 0.8, b: 0.8, index: 0, dashed: false)
    drawLegendItem(label: "JPEG Orig Dec", r: 1, g: 0.9, b: 0.8, index: 1, dashed: false)
    
    drawLegendItem(label: "JPEG Thumb Enc", r: 1, g: 0, b: 0, index: 2, dashed: true)
    drawLegendItem(label: "JPEG Thumb Dec", r: 1, g: 0.5, b: 0, index: 3, dashed: true)
    
    drawLegendItem(label: "JPEG Total", r: 0.5, g: 0, b: 0.5, index: 4, dashed: false, bold: true)

    drawLegendItem(label: "veif Enc", r: 0.8, g: 0.8, b: 1, index: 5, dashed: false)
    drawLegendItem(label: "veif Thumb Dec", r: 0.8, g: 1, b: 1, index: 6, dashed: false)
    
    drawLegendItem(label: "veif Total (Dec)", r: 0, g: 0.5, b: 0, index: 7, dashed: false, bold: true)


    // Axis Titles
    drawText(text: "Time (ms)", x: Double(width) / 2.0, y: 15, context: context, alignCenter: true, fontSize: 16)
    drawRotatedText(text: "MS-SSIM", x: 15, y: Double(height) / 2.0, angle: .pi / 2, context: context, fontSize: 16)
    
    drawText(text: title, x: Double(width) / 2.0, y: Double(height) - 40, context: context, alignCenter: true, fontSize: 24)
    
    return context.makeImage()
}
