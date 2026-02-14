import Foundation

// MARK: - Encode

let k: UInt8 = 1

func toUint16Encode(_ n: Int16) -> UInt16 {
    return UInt16(bitPattern: ((n &<< 1) ^ (n >> 15)))
}

func blockEncode(rw: RiceWriter, block: Block2D, size: Int) {
    for i in 0..<(size * size) {
        rw.write(val: toUint16Encode(block.data[i]), k: k)
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
    
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
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
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
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
        let offset = block.rowOffset(y: i)
        for j in 0..<size {
            block.data[offset + j] = row[j]
        }
    }
    
    let data = NSMutableData(capacity: size * size) ?? NSMutableData()
    let ll = try transformLayer(data: data, block: &block, size: size, scale: scale)
    
    return (data as Data, ll)
}

func transformBaseFunc(rows: RowFunc, w: Int, h: Int, size: Int, scale: Int) throws -> Data {
    var block = Block2D(width: size, height: size)
    for i in 0..<size {
        let row = rows(w, (h + i), size)
        let offset = block.rowOffset(y: i)
        for j in 0..<size {
            block.data[offset + j] = row[j]
        }
    }
    
    let data = NSMutableData(capacity: size * size) ?? NSMutableData()
    try transformBase(data: data, block: &block, size: size, scale: scale)
    
    return data as Data
}

func encodeLayer(r: ImageReader, size: Int, scale: Int) throws -> (Data, Image16) {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []
    
    let dx = r.width
    let dy = r.height
    
    var sub = Image16(width: (dx / 2), height: (dy / 2))
    
    // Y
    for h in stride(from: 0, to: dy, by: size) {
        for w in stride(from: 0, to: dx, by: size) {
            let (data, ll) = try transformLayerFunc(rows: r.rowY, w: w, h: h, size: size, scale: scale)
            bufY.append(data)
            
            sub.updateY(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
        }
    }
    
    // Cb
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let (data, ll) = try transformLayerFunc(rows: r.rowCb, w: w, h: h, size: size, scale: scale)
            bufCb.append(data)
            
            sub.updateCb(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
        }
    }
    
    // Cr
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let (data, ll) = try transformLayerFunc(rows: r.rowCr, w: w, h: h, size: size, scale: scale)
            bufCr.append(data)
            
            sub.updateCr(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
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

func encodeBase(r: ImageReader, size: Int, scale: Int) throws -> Data {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []
    
    let dx = r.width
    let dy = r.height
    
    // Y
    for h in stride(from: 0, to: dy, by: size) {
        for w in stride(from: 0, to: dx, by: size) {
            let data = try transformBaseFunc(rows: r.rowY, w: w, h: h, size: size, scale: scale)
            bufY.append(data)
        }
    }
    
    // Cb
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let data = try transformBaseFunc(rows: r.rowCb, w: w, h: h, size: size, scale: scale)
            bufCb.append(data)
        }
    }
    
    // Cr
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let data = try transformBaseFunc(rows: r.rowCr, w: w, h: h, size: size, scale: scale)
            bufCr.append(data)
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

func estimateBaseScale(img: YCbCrImage, targetBitrate: Int) -> Int {
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
    var totalSize = 0
    let r = ImageReader(img: img)
    
    for (sx, sy) in points {
        // Y
        var block = Block2D(width: w, height: h)
        for i in 0..<h {
            for j in 0..<w {
                block.data[block.rowOffset(y: i) + j] = r.rowY(x: sx + j, y: sy + i, size: w)[0]
            }
        }
        
        let data = NSMutableData(capacity: w * h) ?? NSMutableData()
        let _ = BitWriter(data: data)
        try? transformBase(data: data, block: &block, size: size, scale: baseScale)
        totalSize += data.length
        
        // Cb
        var blockCb = Block2D(width: w, height: h)
        for i in 0..<h {
            for j in 0..<w {
                blockCb.data[blockCb.rowOffset(y: i) + j] = r.rowCb(x: sx + j, y: sy + i, size: w)[0]
            }
        }
        try? transformBase(data: data, block: &blockCb, size: size, scale: baseScale)
        totalSize += data.length
        
        // Cr
        var blockCr = Block2D(width: w, height: h)
        for i in 0..<h {
            for j in 0..<w {
                blockCr.data[blockCr.rowOffset(y: i) + j] = r.rowCr(x: sx + j, y: sy + i, size: w)[0]
            }
        }
        try? transformBase(data: data, block: &blockCr, size: size, scale: baseScale)
        totalSize += data.length
    }
    
    // Total Raw Size of sampled blocks (Y + Cb + Cr)
    // 4:4:4 assumption for simplification in sampling (reading r.rowCb/Cr at same coordinates)
    // Each pixel has Y, Cb, Cr components -> 3 bytes per pixel
    // points.count * (w * h) * 3
    let totalSampleRawSize = (points.count * (w * h) * 3)
    
    // Compression Ratio of samples (Encoded / Raw)
    // Avoid division by zero
    let compressionRatio = (Double(totalSize * 8) / Double(totalSampleRawSize * 8))

    let totalImageRawBits = ((img.yPlane.count + img.cbPlane.count + img.crPlane.count) * 8)

    let estimatedCurrentBitrate = (compressionRatio * Double(totalImageRawBits))
    let adjustmentRatio = (estimatedCurrentBitrate / Double(targetBitrate))
    
    var resultScale: Int
    if 1.0 < adjustmentRatio {
        resultScale = Int((Double(baseScale) * adjustmentRatio) + 0.5)
    } else {
        resultScale = Int((Double(baseScale) * adjustmentRatio) + 0.5)
    }
    
    if resultScale < 1 {
        resultScale = 1
    }
    return resultScale
}

public func encode(img: YCbCrImage, maxbitrate: Int) throws -> Data {
    let scale = estimateBaseScale(img: img, targetBitrate: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try encodeLayer(r: r2, size: 32, scale: scale)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try encodeLayer(r: r1, size: 16, scale: scale)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try encodeBase(r: r0, size: 8, scale: scale)
    
    var out = Data()
    
    withUnsafeBytes(of: UInt32(layer0.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer0)
    
    withUnsafeBytes(of: UInt32(layer1.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer1)
    
    withUnsafeBytes(of: UInt32(layer2.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer2)
    
    return out
}
