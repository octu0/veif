// MARK: - Encode

let k: UInt8 = 1

@inline(__always)
func toUint16(_ n: Int16) -> UInt16 {
    return UInt16(bitPattern: ((n &<< 1) ^ (n >> 15)))
}

@inline(__always)
func blockEncode(rw: inout RiceWriter, block: BlockView, size: Int) {
    for y in 0..<size {
        let ptr = block.rowPointer(y: y)
        for x in 0..<size {
            rw.write(val: UInt16(bitPattern: ptr[x]), k: k)
        }
    }
}

@inline(__always)
func blockEncodeDPCM(rw: inout RiceWriter, block: BlockView, size: Int) {
    var prevVal: Int16 = 0
    for y in 0..<size {
        let ptr = block.rowPointer(y: y)
        for x in 0..<size {
            let val = ptr[x]
            let diff = val - prevVal
            rw.write(val: toUint16(diff), k: k)
            prevVal = val
        }
    }
}

// MARK: - Byte Serialization Helpers

@inline(__always)
func appendUInt16BE(_ out: inout [UInt8], _ val: UInt16) {
    out.append(UInt8(val >> 8))
    out.append(UInt8(val & 0xFF))
}

@inline(__always)
func appendUInt32BE(_ out: inout [UInt8], _ val: UInt32) {
    out.append(UInt8((val >> 24) & 0xFF))
    out.append(UInt8((val >> 16) & 0xFF))
    out.append(UInt8((val >> 8) & 0xFF))
    out.append(UInt8(val & 0xFF))
}

// MARK: - Transform Functions

@inline(__always)
func transformLayer(bw: inout BitWriter, block: inout Block2D, size: Int, qt: QuantizationTable) throws -> Block2D {
    var sub = block.withView { view in
        return dwt2d(&view, size: size)
    }
    
    quantizeMidSignedMapping(&sub.hl, qt: qt)
    quantizeMidSignedMapping(&sub.lh, qt: qt)
    quantizeHighSignedMapping(&sub.hh, qt: qt)
    
    RiceWriter.withWriter(&bw) { rw in
        blockEncode(rw: &rw, block: sub.hl, size: sub.size)
        blockEncode(rw: &rw, block: sub.lh, size: sub.size)
        blockEncode(rw: &rw, block: sub.hh, size: sub.size)
    }
    
    // Return LL as a new Block2D (still needed for next layer's input)
    var llBlock = Block2D(width: sub.size, height: sub.size)
    llBlock.withView { dest in
        let src = sub.ll
        for y in 0..<sub.size {
            let srcPtr = src.rowPointer(y: y)
            let destPtr = dest.rowPointer(y: y)
            destPtr.update(from: srcPtr, count: sub.size)
        }
    }
    return llBlock
}

@inline(__always)
func transformBase(bw: inout BitWriter, block: inout Block2D, size: Int, qt: QuantizationTable) throws {
    var sub = block.withView { view in
        return dwt2d(&view, size: size)
    }
    
    quantizeLow(&sub.ll, qt: qt)
    quantizeMidSignedMapping(&sub.hl, qt: qt)
    quantizeMidSignedMapping(&sub.lh, qt: qt)
    quantizeHighSignedMapping(&sub.hh, qt: qt)
    
    RiceWriter.withWriter(&bw) { rw in
        blockEncodeDPCM(rw: &rw, block: sub.ll, size: sub.size)
        blockEncode(rw: &rw, block: sub.hl, size: sub.size)
        blockEncode(rw: &rw, block: sub.lh, size: sub.size)
        blockEncode(rw: &rw, block: sub.hh, size: sub.size)
    }
}

@inline(__always)
func transformLayerFunc(rows: RowFunc, w: Int, h: Int, size: Int, qt: QuantizationTable) throws -> ([UInt8], Block2D) {
    var block = Block2D(width: size, height: size)
    block.withView { view in
        for i in 0..<size {
            let row = rows(w, (h + i), size)
            view.setRow(offsetY: i, row: row)
        }
    }
    
    var bw = BitWriter()
    let ll = try transformLayer(bw: &bw, block: &block, size: size, qt: qt)
    
    return (bw.data, ll)
}

@inline(__always)
func transformBaseFunc(rows: RowFunc, w: Int, h: Int, size: Int, qt: QuantizationTable) throws -> [UInt8] {
    var block = Block2D(width: size, height: size)
    block.withView { view in
        for i in 0..<size {
            let row = rows(w, (h + i), size)
            view.setRow(offsetY: i, row: row)
        }
    }
    
    var bw = BitWriter()
    try transformBase(bw: &bw, block: &block, size: size, qt: qt)
    
    return bw.data
}

// MARK: - Encode Layer / Base

func encodeLayer(r: ImageReader, layer: UInt8, size: Int, qt: QuantizationTable) async throws -> ([UInt8], Image16) {
    var bufY: [[UInt8]] = []
    var bufCb: [[UInt8]] = []
    var bufCr: [[UInt8]] = []
    
    let dx = r.width
    let dy = r.height
    
    var sub = Image16(width: (dx / 2), height: (dy / 2))
    
    // Y
    try await withThrowingTaskGroup(of: (Int, [([UInt8], Block2D, Int, Int)]).self) { group in
        for h in stride(from: 0, to: dy, by: size) {
            group.addTask {
                var rowResults: [([UInt8], Block2D, Int, Int)] = []
                for w in stride(from: 0, to: dx, by: size) {
                    let (data, ll) = try transformLayerFunc(rows: r.rowY, w: w, h: h, size: size, qt: qt)
                    rowResults.append((data, ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [([UInt8], Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for i in results.indices {
            for j in results[i].1.indices {
                let (data, _, w, h) = results[i].1[j]
                bufY.append(data)
                sub.updateY(data: &results[i].1[j].1, startX: (w / 2), startY: (h / 2), size: (size / 2))
            }
        }
    }
    
    // Cb
    try await withThrowingTaskGroup(of: (Int, [([UInt8], Block2D, Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [([UInt8], Block2D, Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let (data, ll) = try transformLayerFunc(rows: r.rowCb, w: w, h: h, size: size, qt: qt)
                    rowResults.append((data, ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [([UInt8], Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for i in results.indices {
            for j in results[i].1.indices {
                let (data, _, w, h) = results[i].1[j]
                bufCb.append(data)
                sub.updateCb(data: &results[i].1[j].1, startX: (w / 2), startY: (h / 2), size: (size / 2))
            }
        }
    }
    
    // Cr
    try await withThrowingTaskGroup(of: (Int, [([UInt8], Block2D, Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [([UInt8], Block2D, Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let (data, ll) = try transformLayerFunc(rows: r.rowCr, w: w, h: h, size: size, qt: qt)
                    rowResults.append((data, ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [([UInt8], Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for i in results.indices {
            for j in results[i].1.indices {
                let (data, _, w, h) = results[i].1[j]
                bufCr.append(data)
                sub.updateCr(data: &results[i].1[j].1, startX: (w / 2), startY: (h / 2), size: (size / 2))
            }
        }
    }
    
    var out: [UInt8] = []
    out.append(contentsOf: [0x56, 0x45, 0x49, 0x46, layer]) // 'VEIF' + layer
    appendUInt16BE(&out, UInt16(dx))
    appendUInt16BE(&out, UInt16(dy))
    out.append(UInt8(qt.step))
    
    appendUInt16BE(&out, UInt16(bufY.count))
    for b in bufY {
        appendUInt16BE(&out, UInt16(b.count))
        out.append(contentsOf: b)
    }
    
    appendUInt16BE(&out, UInt16(bufCb.count))
    for b in bufCb {
        appendUInt16BE(&out, UInt16(b.count))
        out.append(contentsOf: b)
    }
    
    appendUInt16BE(&out, UInt16(bufCr.count))
    for b in bufCr {
        appendUInt16BE(&out, UInt16(b.count))
        out.append(contentsOf: b)
    }
    
    return (out, sub)
}

func encodeBase(r: ImageReader, layer: UInt8, size: Int, qt: QuantizationTable) async throws -> [UInt8] {
    var bufY: [[UInt8]] = []
    var bufCb: [[UInt8]] = []
    var bufCr: [[UInt8]] = []
    
    let dx = r.width
    let dy = r.height
    
    // Y
    try await withThrowingTaskGroup(of: (Int, [([UInt8], Int, Int)]).self) { group in
        for h in stride(from: 0, to: dy, by: size) {
            group.addTask {
                var rowResults: [([UInt8], Int, Int)] = []
                for w in stride(from: 0, to: dx, by: size) {
                    let data = try transformBaseFunc(rows: r.rowY, w: w, h: h, size: size, qt: qt)
                    rowResults.append((data, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [([UInt8], Int, Int)])] = []
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
    try await withThrowingTaskGroup(of: (Int, [([UInt8], Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [([UInt8], Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let data = try transformBaseFunc(rows: r.rowCb, w: w, h: h, size: size, qt: qt)
                    rowResults.append((data, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [([UInt8], Int, Int)])] = []
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
    try await withThrowingTaskGroup(of: (Int, [([UInt8], Int, Int)]).self) { group in
        for h in stride(from: 0, to: (dy / 2), by: size) {
            group.addTask {
                var rowResults: [([UInt8], Int, Int)] = []
                for w in stride(from: 0, to: (dx / 2), by: size) {
                    let data = try transformBaseFunc(rows: r.rowCr, w: w, h: h, size: size, qt: qt)
                    rowResults.append((data, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [([UInt8], Int, Int)])] = []
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
    
    var out: [UInt8] = []
    out.append(contentsOf: [0x56, 0x45, 0x49, 0x46, layer]) // 'VEIF' + layer
    appendUInt16BE(&out, UInt16(dx))
    appendUInt16BE(&out, UInt16(dy))
    out.append(UInt8(qt.step))
    
    appendUInt16BE(&out, UInt16(bufY.count))
    for b in bufY {
        appendUInt16BE(&out, UInt16(b.count))
        out.append(contentsOf: b)
    }
    
    appendUInt16BE(&out, UInt16(bufCb.count))
    for b in bufCb {
        appendUInt16BE(&out, UInt16(b.count))
        out.append(contentsOf: b)
    }
    
    appendUInt16BE(&out, UInt16(bufCr.count))
    for b in bufCr {
        appendUInt16BE(&out, UInt16(b.count))
        out.append(contentsOf: b)
    }
    
    return out
}

// MARK: - Estimation Functions

private func estimateRiceBitsDPCM(block: BlockView, size: Int) -> Int {
    var sumDiffAbs = 0
    let count = size * size
    var prev: Int16 = 0
    
    for y in 0..<size {
        let ptr = block.rowPointer(y: y)
        for x in 0..<size {
            let val = ptr[x]
            let diff = abs(Int(val - prev))
            sumDiffAbs += diff
            prev = val
        }
    }
    
    if count == 0 { return 0 }
    
    let mean = Double(sumDiffAbs) / Double(count)
    let meanInt = Int(mean)
    let k = (meanInt < 1) ? 0 : (Int.bitWidth - 1 - meanInt.leadingZeroBitCount)
    
    let divisorShift = max(0, k - 1)
    let bodyBits = sumDiffAbs >> divisorShift
    let headerBits = count * (1 + k)
    
    return bodyBits + headerBits
}

private func fetchBlock(reader: ImageReader, plane: PlaneType, x: Int, y: Int, w: Int, h: Int) -> Block2D {
    var block = Block2D(width: w, height: h)
    block.withView { view in
        for i in 0..<h {
            let row: [Int16]
            switch plane {
            case .y:  row = reader.rowY(x: x, y: y + i, size: w)
            case .cb: row = reader.rowCb(x: x, y: y + i, size: w)
            case .cr: row = reader.rowCr(x: x, y: y + i, size: w)
            }
            view.setRow(offsetY: i, row: row)
        }
    }
    return block
}

private enum PlaneType { case y, cb, cr }

private func measureBlockBits(block: inout Block2D, size: Int, qt: QuantizationTable) -> Int {
    var sub = block.withView { view in
        return dwt2d(&view, size: size)
    }
    
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

private func estimateRiceBits(block: BlockView, size: Int) -> Int {
    var sumAbs = 0
    let count = size * size
    
    for y in 0..<size {
        let ptr = block.rowPointer(y: y)
        for x in 0..<size {
            sumAbs += abs(Int(ptr[x]))
        }
    }
    
    if count == 0 { return 0 }
    
    let mean = Double(sumAbs) / Double(count)
    let meanInt = Int(mean)
    let k = (meanInt < 1) ? 0 : (Int.bitWidth - 1 - meanInt.leadingZeroBitCount)
    
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

// MARK: - Public API ([UInt8] based, Foundation-free)

public func encode(img: YCbCrImage, maxbitrate: Int) async throws -> [UInt8] {
    let qt = estimateQuantization(img: img, targetBits: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try await encodeLayer(r: r2, layer: 2, size: 32, qt: qt)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try await encodeLayer(r: r1, layer: 1, size: 16, qt: qt)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try await encodeBase(r: r0, layer: 0, size: 8, qt: qt)
    
    var out: [UInt8] = []
    
    appendUInt32BE(&out, UInt32(layer0.count))
    out.append(contentsOf: layer0)
    
    appendUInt32BE(&out, UInt32(layer1.count))
    out.append(contentsOf: layer1)
    
    appendUInt32BE(&out, UInt32(layer2.count))
    out.append(contentsOf: layer2)
    
    return out
}

public func encodeLayers(img: YCbCrImage, maxbitrate: Int) async throws -> ([UInt8], [UInt8], [UInt8]) {
    let qt = estimateQuantization(img: img, targetBits: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try await encodeLayer(r: r2, layer: 2, size: 32, qt: qt)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try await encodeLayer(r: r1, layer: 1, size: 16, qt: qt)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try await encodeBase(r: r0, layer: 0, size: 8, qt: qt)
    
    return (layer0, layer1, layer2)
}

public func encodeOne(img: YCbCrImage, maxbitrate: Int) async throws -> [UInt8] {
   let qt = estimateQuantization(img: img, targetBits: maxbitrate)

    let r = ImageReader(img: img)
    let layer = try await encodeBase(r: r, layer: 0, size: 32, qt: qt)

    var out: [UInt8] = []
    
    appendUInt32BE(&out, UInt32(layer.count))
    out.append(contentsOf: layer)
    
    return out
}


