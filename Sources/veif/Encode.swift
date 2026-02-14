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

func transformLayer(bw: BitWriter, block: inout Block2D, size: Int, scale: Int) throws -> Block2D {
    var sub = dwt2d(&block, size: size)
    
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
    let rw = RiceWriter(bw: bw)
    blockEncode(rw: rw, block: sub.hl, size: sub.size)
    blockEncode(rw: rw, block: sub.lh, size: sub.size)
    blockEncode(rw: rw, block: sub.hh, size: sub.size)
    rw.flush()
    
    return sub.ll
}

func transformBase(bw: BitWriter, block: inout Block2D, size: Int, scale: Int) throws {
    var sub = dwt2d(&block, size: size)
    
    quantizeLow(&sub.ll, size: sub.size, scale: scale)
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
    let rw = RiceWriter(bw: bw)
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
    
    var data = Data(capacity: size * size)
    let bw = BitWriter(data: &data)
    let ll = try transformLayer(bw: bw, block: &block, size: size, scale: scale)
    
    return (data, ll)
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
    
    var data = Data(capacity: size * size)
    let bw = BitWriter(data: &data)
    try transformBase(bw: bw, block: &block, size: size, scale: scale)
    
    return data
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
    return 0
}

public func encode(img: YCbCrImage, maxbitrate: Int) throws -> Data {
    let baseScale = estimateBaseScale(img: img, targetBitrate: maxbitrate)

    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try encodeLayer(r: r2, size: 32, scale: baseScale)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try encodeLayer(r: r1, size: 16, scale: baseScale)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try encodeBase(r: r0, size: 8, scale: baseScale)
    
    var out = Data()
    
    withUnsafeBytes(of: UInt32(layer0.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer0)
    
    withUnsafeBytes(of: UInt32(layer1.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer1)
    
    withUnsafeBytes(of: UInt32(layer2.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer2)
    
    return out
}
