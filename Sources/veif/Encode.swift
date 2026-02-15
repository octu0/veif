import Foundation

// MARK: - Encode

let k: UInt8 = 1

func toUint16Encode(_ n: Int16) -> UInt16 {
    return UInt16(bitPattern: ((n &<< 1) ^ (n >> 15)))
}

func blockEncode(rw: RiceWriter, block: Block2D, size: Int) {
    for i in 0..<(size * size) {
        rw.write(val: UInt16(bitPattern: block.data[i]), k: k)
    }
}

func blockEncodeDPCM(rw: RiceWriter, block: Block2D, size: Int) {
    var prevVal: Int16 = 0
    for i in 0..<(size * size) {
        let val = block.data[i]
        let diff = val - prevVal
        rw.write(val: toUint16Encode(diff), k: k)
        prevVal = val
    }
}

func transformLayer(data: NSMutableData, block: inout Block2D, size: Int, scale: Int) throws -> Block2D {
    var sub = dwt2d(&block, size: size)
    
    quantizeMidSignedMapping(&sub.hl, size: sub.size, scale: scale)
    quantizeMidSignedMapping(&sub.lh, size: sub.size, scale: scale)
    quantizeHighSignedMapping(&sub.hh, size: sub.size, scale: scale)
    
    let rw = RiceWriter(bw: BitWriter(data: data))
    blockEncode(rw: rw, block: sub.hl, size: sub.size)
    blockEncode(rw: rw, block: sub.lh, size: sub.size)
    blockEncode(rw: rw, block: sub.hh, size: sub.size)
    rw.flush()
    
    return sub.ll
}

func transformBase(data: NSMutableData, block: inout Block2D, size: Int, scale: Int) throws {
    var sub = dwt2d(&block, size: size)
    
    quantizeLow(&sub.ll, size: sub.size, scale: scale)
    quantizeMidSignedMapping(&sub.hl, size: sub.size, scale: scale)
    quantizeMidSignedMapping(&sub.lh, size: sub.size, scale: scale)
    quantizeHighSignedMapping(&sub.hh, size: sub.size, scale: scale)
    
    let rw = RiceWriter(bw: BitWriter(data: data))
    blockEncodeDPCM(rw: rw, block: sub.ll, size: sub.size)
    blockEncode(rw: rw, block: sub.hl, size: sub.size)
    blockEncode(rw: rw, block: sub.lh, size: sub.size)
    blockEncode(rw: rw, block: sub.hh, size: sub.size)
    rw.flush()
}

func transformLayerFunc(rows: RowFunc, w: Int, h: Int, size: Int, scale: Int) throws -> (Data, Block2D) {
    var block = Block2D(width: size, height: size)
    for i in 0..<size {
        let row = rows(w, (h + i), size)
        block.setRow(offsetY: i, size: size, row: row)
    }
    
    let data = NSMutableData(capacity: size * size) ?? NSMutableData()
    let ll = try transformLayer(data: data, block: &block, size: size, scale: scale)
    
    return (data as Data, ll)
}

func transformBaseFunc(rows: RowFunc, w: Int, h: Int, size: Int, scale: Int) throws -> Data {
    var block = Block2D(width: size, height: size)
    for i in 0..<size {
        let row = rows(w, (h + i), size)
        block.setRow(offsetY: i, size: size, row: row)
    }
    
    let data = NSMutableData(capacity: size * size) ?? NSMutableData()
    try transformBase(data: data, block: &block, size: size, scale: scale)
    
    return data as Data
}

func encodeLayer(r: ImageReader, size: Int, scale: Int) async throws -> (Data, Image16) {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []
    
    let dx = r.width
    let dy = r.height
    
    var sub = Image16(width: (dx / 2), height: (dy / 2))
    
    // Y
    try await withThrowingTaskGroup(of: (Int, [(Data, Block2D, Int, Int)]).self) { group in
        for h in stride(from: 0, to: dy, by: size) {
            group.addTask {
                var rowResults: [(Data, Block2D, Int, Int)] = []
                for w in stride(from: 0, to: dx, by: size) {
                    let (data, ll) = try transformLayerFunc(rows: r.rowY, w: w, h: h, size: size, scale: scale)
                    rowResults.append((data, ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Data, Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (data, ll, w, h) in rowBlocks {
                bufY.append(data)
                sub.updateY(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
            }
        }
    }
    
    // Cb
    try await withThrowingTaskGroup(of: (Int, [(Data, Block2D, Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [(Data, Block2D, Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let (data, ll) = try transformLayerFunc(rows: r.rowCb, w: w, h: h, size: size, scale: scale)
                    rowResults.append((data, ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Data, Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (data, ll, w, h) in rowBlocks {
                bufCb.append(data)
                sub.updateCb(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
            }
        }
    }
    
    // Cr
    try await withThrowingTaskGroup(of: (Int, [(Data, Block2D, Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [(Data, Block2D, Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let (data, ll) = try transformLayerFunc(rows: r.rowCr, w: w, h: h, size: size, scale: scale)
                    rowResults.append((data, ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Data, Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (data, ll, w, h) in rowBlocks {
                bufCr.append(data)
                sub.updateCr(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
            }
        }
    }
    
    var out = Data()
    withUnsafeBytes(of: UInt16(dx).bigEndian) { out.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt16(dy).bigEndian) { out.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt8(scale).bigEndian) { out.append(contentsOf: $0) }
    
    withUnsafeBytes(of: UInt16(bufY.count).bigEndian) { out.append(contentsOf: $0) }
    for b in bufY {
        withUnsafeBytes(of: UInt16(b.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(b)
    }
    
    withUnsafeBytes(of: UInt16(bufCb.count).bigEndian) { out.append(contentsOf: $0) }
    for b in bufCb {
        withUnsafeBytes(of: UInt16(b.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(b)
    }
    
    withUnsafeBytes(of: UInt16(bufCr.count).bigEndian) { out.append(contentsOf: $0) }
    for b in bufCr {
        withUnsafeBytes(of: UInt16(b.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(b)
    }
    
    return (out, sub)
}

func encodeBase(r: ImageReader, size: Int, scale: Int) async throws -> Data {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []
    
    let dx = r.width
    let dy = r.height
    
    // Y
    try await withThrowingTaskGroup(of: (Int, [(Data, Int, Int)]).self) { group in
        for h in stride(from: 0, to: dy, by: size) {
            group.addTask {
                var rowResults: [(Data, Int, Int)] = []
                for w in stride(from: 0, to: dx, by: size) {
                    let data = try transformBaseFunc(rows: r.rowY, w: w, h: h, size: size, scale: scale)
                    rowResults.append((data, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Data, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (data, _, _) in rowBlocks {
                bufY.append(data)
            }
        }
    }
    
    // Cb
    try await withThrowingTaskGroup(of: (Int, [(Data, Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [(Data, Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let data = try transformBaseFunc(rows: r.rowCb, w: w, h: h, size: size, scale: scale)
                    rowResults.append((data, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Data, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (data, _, _) in rowBlocks {
                bufCb.append(data)
            }
        }
    }
    
    // Cr
    try await withThrowingTaskGroup(of: (Int, [(Data, Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [(Data, Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let data = try transformBaseFunc(rows: r.rowCr, w: w, h: h, size: size, scale: scale)
                    rowResults.append((data, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Data, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (data, _, _) in rowBlocks {
                bufCr.append(data)
            }
        }
    }
    
    var out = Data()
    withUnsafeBytes(of: UInt16(dx).bigEndian) { out.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt16(dy).bigEndian) { out.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt8(scale).bigEndian) { out.append(contentsOf: $0) }
    
    withUnsafeBytes(of: UInt16(bufY.count).bigEndian) { out.append(contentsOf: $0) }
    for b in bufY {
        withUnsafeBytes(of: UInt16(b.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(b)
    }
    
    withUnsafeBytes(of: UInt16(bufCb.count).bigEndian) { out.append(contentsOf: $0) }
    for b in bufCb {
        withUnsafeBytes(of: UInt16(b.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(b)
    }
    
    withUnsafeBytes(of: UInt16(bufCr.count).bigEndian) { out.append(contentsOf: $0) }
    for b in bufCr {
        withUnsafeBytes(of: UInt16(b.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(b)
    }
    
    return out
}

private func measureBlockBits(block: inout Block2D, size: Int, scale: Int) -> Int {
    var sub = dwt2d(&block, size: size)
    
    quantizeLow(&sub.ll, size: sub.size, scale: scale)
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
    var totalBits = 0
    
    totalBits += estimateSumBitsDPCM(block: sub.ll, size: sub.size)
    totalBits += estimateSumBits(block: sub.hl, size: sub.size)
    totalBits += estimateSumBits(block: sub.lh, size: sub.size)
    totalBits += estimateSumBits(block: sub.hh, size: sub.size)
    
    return totalBits
}

@inline(__always)
private func estimateSumBits(block: Block2D, size: Int) -> Int {
    var bits = 0
    block.data.withUnsafeBufferPointer { ptr in
        for i in 0..<(size * size) {
            let val = abs(Int(ptr[i]))
            if val == 0 {
                bits += 1 
            } else {
                // Rice (k=1) bit count approx:
                // q = val / 2
                // output = q '1's + 1 '0' + remaining 1 bit = q + 2 bits
                // e.g.: 3 -> 1101 (4bit) vs estimate(1+2=3bit) ...
                bits += (val >> 1) + 2
            }
        }
    }
    return bits
}

@inline(__always)
private func estimateSumBitsDPCM(block: Block2D, size: Int) -> Int {
    var bits = 0
    var prevVal: Int16 = 0
    
    block.data.withUnsafeBufferPointer { ptr in
        for i in 0..<(size * size) {
            let val = ptr[i]
            let diff = abs(Int(val - prevVal))
            
            if diff == 0 {
                bits += 1
            } else {
                bits += (diff >> 1) + 2
            }
            prevVal = val
        }
    }
    return bits
}

private func estimateBaseScale(img: YCbCrImage, targetBitrate: Int) -> Int {
    // 8 points
    let size = 8
    let w = (img.width / size)
    let h = (img.height / size)
    let points: [(Int, Int)] = [
        (0, 0),                                    // TL
        ((img.width - w), 0),                      // TR
        (0, (img.height - h)),                     // BL
        ((img.width - w), (img.height - h)),       // BR
        (((img.width - w) / 2), 0),                // TC
        ((img.width - w), ((img.height - h) / 2)), // RC
        (((img.width - w) / 2), (img.height - h)), // BC
        (0, ((img.height - h) / 2)),               // LC
    ]
    
    let baseScale = 1
    var totalEstimatedBits = 0
    let r = ImageReader(img: img)
    
    // Sampling loop
    for (sx, sy) in points {
        // Y Plane
        var block = Block2D(width: w, height: h)
        for i in 0..<h {
            let row = r.rowY(x: sx, y: sy + i, size: w)
            block.setRow(offsetY: i, size: w, row: row)
        }
        totalEstimatedBits += measureBlockBits(block: &block, size: size, scale: baseScale)
        
        // Cb Plane
        var blockCb = Block2D(width: w, height: h)
        for i in 0..<h {
            let row = r.rowCb(x: sx, y: sy + i, size: w)
            blockCb.setRow(offsetY: i, size: w, row: row)
        }
        totalEstimatedBits += measureBlockBits(block: &blockCb, size: size, scale: baseScale)
        
        // Cr Plane
        var blockCr = Block2D(width: w, height: h)
        for i in 0..<h {
            let row = r.rowCr(x: sx, y: sy + i, size: w)
            blockCr.setRow(offsetY: i, size: w, row: row)
        }
        totalEstimatedBits += measureBlockBits(block: &blockCr, size: size, scale: baseScale)
    }
    
    // Estimated total bits (for sampling)
    let estimatedSampleBits = Double(totalEstimatedBits)
    
    // Total pixel bits of original image (Y+Cb+Cr) * 8
    let totalImageRawBits = Double((img.yPlane.count + img.cbPlane.count + img.crPlane.count) * 8)
    
    // Raw data size of sampled area (bits)
    // points.count * (w * h) pixels * 3ch * 8bit
    let sampleRawBits = Double(points.count * (w * h) * 3 * 8)
    
    // Compression ratio = Estimated compressed bits / Sample raw bits
    let compressionRatio = estimatedSampleBits / sampleRawBits
    
    // Estimated bitrate when applied to the entire image
    let estimatedCurrentBitrate = compressionRatio * totalImageRawBits
    
    let adjustmentRatio = estimatedCurrentBitrate / Double(targetBitrate)
    
    // Determine the new scale (simple proportional model)
    var resultScale: Int
    if 1.0 > adjustmentRatio {
        // Bitrate exceeded -> Increase scale to improve compression ratio
        resultScale = Int((Double(baseScale) * adjustmentRatio) + 0.5)
    } else {
        resultScale = Int((Double(baseScale) * adjustmentRatio) - 0.5)
    }
    
    return max(1, resultScale)
}

public func encode(img: YCbCrImage, maxbitrate: Int) async throws -> Data {
    let scale = estimateBaseScale(img: img, targetBitrate: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try await encodeLayer(r: r2, size: 32, scale: scale)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try await encodeLayer(r: r1, size: 16, scale: scale)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try await encodeBase(r: r0, size: 8, scale: scale)
    
    var out = Data()
    
    withUnsafeBytes(of: UInt32(layer0.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer0)
    
    withUnsafeBytes(of: UInt32(layer1.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer1)
    
    withUnsafeBytes(of: UInt32(layer2.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer2)
    
    return out
}

public func encodeLayers(img: YCbCrImage, maxbitrate: Int) async throws -> (Data, Data, Data) {
    let scale = estimateBaseScale(img: img, targetBitrate: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try await encodeLayer(r: r2, size: 32, scale: scale)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try await encodeLayer(r: r1, size: 16, scale: scale)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try await encodeBase(r: r0, size: 8, scale: scale)
    
    return (layer0, layer1, layer2)
}

public func encodeOne(img: YCbCrImage, maxbitrate: Int) async throws -> Data {
   let scale = estimateBaseScale(img: img, targetBitrate: maxbitrate)

    let r = ImageReader(img: img)
    let layer = try await encodeBase(r: r, size: 32, scale: scale)

    var out = Data()
    
    withUnsafeBytes(of: UInt32(layer.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer)
    
    return out
}