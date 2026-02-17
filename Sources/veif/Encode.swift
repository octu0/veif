import Foundation

// MARK: - Encode

let k: UInt8 = 1

@inline(__always)
func toUint16(_ n: Int16) -> UInt16 {
    return UInt16(bitPattern: ((n &<< 1) ^ (n >> 15)))
}

@inline(__always)
func blockEncode(rw: inout RiceWriter, block: Block2D, size: Int) {
    for i in 0..<(size * size) {
        rw.write(val: UInt16(bitPattern: block.data[i]), k: k)
    }
}

@inline(__always)
func blockEncodeDPCM(rw: inout RiceWriter, block: Block2D, size: Int) {
    var prevVal: Int16 = 0
    for i in 0..<(size * size) {
        let val = block.data[i]
        let diff = val - prevVal
        rw.write(val: toUint16(diff), k: k)
        prevVal = val
    }
}

@inline(__always)
func transformLayer(data: NSMutableData, block: inout Block2D, size: Int, qt: QuantizationTable) throws -> Block2D {
    var sub = dwt2d(&block, size: size)
    
    quantizeMidSignedMapping(&sub.hl, qt: qt)
    quantizeMidSignedMapping(&sub.lh, qt: qt)
    quantizeHighSignedMapping(&sub.hh, qt: qt)
    
    var rw = RiceWriter(bw: BitWriter(data: data))
    blockEncode(rw: &rw, block: sub.hl, size: sub.size)
    blockEncode(rw: &rw, block: sub.lh, size: sub.size)
    blockEncode(rw: &rw, block: sub.hh, size: sub.size)
    rw.flush()
    
    return sub.ll
}

@inline(__always)
func transformBase(data: NSMutableData, block: inout Block2D, size: Int, qt: QuantizationTable) throws {
    var sub = dwt2d(&block, size: size)
    
    quantizeLow(&sub.ll, qt: qt)
    quantizeMidSignedMapping(&sub.hl, qt: qt)
    quantizeMidSignedMapping(&sub.lh, qt: qt)
    quantizeHighSignedMapping(&sub.hh, qt: qt)
    
    var rw = RiceWriter(bw: BitWriter(data: data))
    blockEncodeDPCM(rw: &rw, block: sub.ll, size: sub.size)
    blockEncode(rw: &rw, block: sub.hl, size: sub.size)
    blockEncode(rw: &rw, block: sub.lh, size: sub.size)
    blockEncode(rw: &rw, block: sub.hh, size: sub.size)
    rw.flush()
}

@inline(__always)
func transformLayerFunc(rows: RowFunc, w: Int, h: Int, size: Int, qt: QuantizationTable) throws -> (Data, Block2D) {
    var block = Block2D(width: size, height: size)
    for i in 0..<size {
        let row = rows(w, (h + i), size)
        block.setRow(offsetY: i, size: size, row: row)
    }
    
    let data = NSMutableData(capacity: size * size) ?? NSMutableData()
    let ll = try transformLayer(data: data, block: &block, size: size, qt: qt)
    
    return (data as Data, ll)
}

@inline(__always)
func transformBaseFunc(rows: RowFunc, w: Int, h: Int, size: Int, qt: QuantizationTable) throws -> Data {
    var block = Block2D(width: size, height: size)
    for i in 0..<size {
        let row = rows(w, (h + i), size)
        block.setRow(offsetY: i, size: size, row: row)
    }
    
    let data = NSMutableData(capacity: size * size) ?? NSMutableData()
    try transformBase(data: data, block: &block, size: size, qt: qt)
    
    return data as Data
}

func encodeLayer(r: ImageReader, size: Int, qt: QuantizationTable) async throws -> (Data, Image16) {
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
                    let (data, ll) = try transformLayerFunc(rows: r.rowY, w: w, h: h, size: size, qt: qt)
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
                    let (data, ll) = try transformLayerFunc(rows: r.rowCb, w: w, h: h, size: size, qt: qt)
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
                    let (data, ll) = try transformLayerFunc(rows: r.rowCr, w: w, h: h, size: size, qt: qt)
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
    withUnsafeBytes(of: UInt8(qt.step).bigEndian) { out.append(contentsOf: $0) }
    
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

func encodeBase(r: ImageReader, size: Int, qt: QuantizationTable) async throws -> Data {
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
                    let data = try transformBaseFunc(rows: r.rowY, w: w, h: h, size: size, qt: qt)
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
                    let data = try transformBaseFunc(rows: r.rowCb, w: w, h: h, size: size, qt: qt)
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
                    let data = try transformBaseFunc(rows: r.rowCr, w: w, h: h, size: size, qt: qt)
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
    withUnsafeBytes(of: UInt8(qt.step).bigEndian) { out.append(contentsOf: $0) }
    
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

private func estimateRiceBitsDPCM(block: Block2D, size: Int) -> Int {
    var sumDiffAbs = 0
    var count = 0
    var prev: Int16 = 0
    
    block.data.withUnsafeBufferPointer { ptr in
        let len = size * size
        count = len
        for i in 0..<len {
            let val = ptr[i]
            let diff = abs(Int(val - prev))
            sumDiffAbs += diff
            prev = val
        }
    }
    
    if count == 0 { return 0 }
    
    let mean = Double(sumDiffAbs) / Double(count)
    let k = (mean < 1.0) ? 0 : Int(log2(mean))
    
    let divisorShift = max(0, k - 1)
    let bodyBits = sumDiffAbs >> divisorShift
    let headerBits = count * (1 + k)
    
    return bodyBits + headerBits
}

private func fetchBlock(reader: ImageReader, plane: PlaneType, x: Int, y: Int, w: Int, h: Int) -> Block2D {
    var block = Block2D(width: w, height: h)
    for i in 0..<h {
        let row: [Int16]
        switch plane {
        case .y:  row = reader.rowY(x: x, y: y + i, size: w)
        case .cb: row = reader.rowCb(x: x, y: y + i, size: w)
        case .cr: row = reader.rowCr(x: x, y: y + i, size: w)
        }
        block.setRow(offsetY: i, size: w, row: row)
    }
    return block
}

private enum PlaneType { case y, cb, cr }

private func measureBlockBits(block: inout Block2D, size: Int, qt: QuantizationTable) -> Int {
    var sub = dwt2d(&block, size: size)
    
    quantizeLow(&sub.ll, qt: qt)
    quantizeMid(&sub.hl, qt: qt)
    quantizeMid(&sub.lh, qt: qt)
    quantizeHigh(&sub.hh, qt: qt)
    
    var bits = 0
    bits += estimateRiceBitsDPCM(block: sub.ll, size: sub.size)
    bits += estimateRiceBits(block: sub.hl, size: sub.size)
    bits += estimateRiceBits(block: sub.lh, size: sub.size)
    bits += estimateRiceBits(block: sub.hh, size: sub.size)
    
    return bits
}

private func estimateRiceBits(block: Block2D, size: Int) -> Int {
    var sumAbs = 0
    var count = 0
    
    block.data.withUnsafeBufferPointer { ptr in
        let len = size * size
        count = len
        for i in 0..<len {
            sumAbs += abs(Int(ptr[i]))
        }
    }
    
    if count == 0 { return 0 }
    
    let mean = Double(sumAbs) / Double(count)
    let k = (mean < 1.0) ? 0 : Int(log2(mean))
    
    let divisorShift = max(0, k - 1)
    let bodyBits = sumAbs >> divisorShift
    let headerBits = count * (1 + k)
    
    return bodyBits + headerBits
}

func estimateQuantization(img: YCbCrImage, targetBits: Int) -> QuantizationTable {
    let probeStep = 64
    let qt = QuantizationTable(baseStep: probeStep)
    
    let size = 8
    let w = (img.width / size)
    let h = (img.height / size)
    
    let points: [(Int, Int)] = [
        (0, 0),                                    // Top-Left
        ((img.width - w), 0),                      // Top-Right
        (0, (img.height - h)),                     // Bottom-Left
        ((img.width - w), (img.height - h)),       // Bottom-Right
        (((img.width - w) / 2), 0),                // Top-Center
        ((img.width - w), ((img.height - h) / 2)), // Right-Center
        (((img.width - w) / 2), (img.height - h)), // Bottom-Center
        (0, ((img.height - h) / 2)),               // Left-Center
    ]
    
    var totalSampleBits = 0
    let reader = ImageReader(img: img)
    
    for (sx, sy) in points {
        // Y Plane
        var blockY = fetchBlock(reader: reader, plane: .y, x: sx, y: sy, w: w, h: h)
        totalSampleBits += measureBlockBits(block: &blockY, size: size, qt: qt)
        
        // Cb Plane
        var blockCb = fetchBlock(reader: reader, plane: .cb, x: sx, y: sy, w: w, h: h)
        totalSampleBits += measureBlockBits(block: &blockCb, size: size, qt: qt)
        
        // Cr Plane
        var blockCr = fetchBlock(reader: reader, plane: .cr, x: sx, y: sy, w: w, h: h)
        totalSampleBits += measureBlockBits(block: &blockCr, size: size, qt: qt)
    }
    
    let samplePixels = points.count * (w * h) * 3 // Y+Cb+Cr
    let totalPixels = img.width * img.height * 3
    
    let estimatedTotalBits = Double(totalSampleBits) * (Double(totalPixels) / Double(samplePixels))
        
    let ratio = estimatedTotalBits / Double(targetBits)
    let predictedStep = Double(probeStep) * ratio
    
    return QuantizationTable(baseStep: Int(predictedStep))
}

public func encode(img: YCbCrImage, maxbitrate: Int) async throws -> Data {
    let qt = estimateQuantization(img: img, targetBits: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try await encodeLayer(r: r2, size: 32, qt: qt)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try await encodeLayer(r: r1, size: 16, qt: qt)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try await encodeBase(r: r0, size: 8, qt: qt)
    
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
    let qt = estimateQuantization(img: img, targetBits: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try await encodeLayer(r: r2, size: 32, qt: qt)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try await encodeLayer(r: r1, size: 16, qt: qt)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try await encodeBase(r: r0, size: 8, qt: qt)
    
    return (layer0, layer1, layer2)
}

public func encodeOne(img: YCbCrImage, maxbitrate: Int) async throws -> Data {
   let qt = estimateQuantization(img: img, targetBits: maxbitrate)

    let r = ImageReader(img: img)
    let layer = try await encodeBase(r: r, size: 32, qt: qt)

    var out = Data()
    
    withUnsafeBytes(of: UInt32(layer.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer)
    
    return out
}
