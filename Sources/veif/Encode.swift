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

func transformLayer(bw: BitWriter, data: inout Block2D, size: Int, scale: Int) throws -> Block2D {
    var sub = dwt2d(&data, size: size)
    
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
    // Write scale
    bw.data.append(UInt8(scale))
    
    let rw = RiceWriter(bw: bw)
    blockEncode(rw: rw, block: sub.hl, size: sub.size)
    blockEncode(rw: rw, block: sub.lh, size: sub.size)
    blockEncode(rw: rw, block: sub.hh, size: sub.size)
    rw.flush()
    
    return sub.ll
}

func transformBase(bw: BitWriter, data: inout Block2D, size: Int, scale: Int) throws {
    var sub = dwt2d(&data, size: size)
    
    quantizeLow(&sub.ll, size: sub.size, scale: scale)
    quantizeMid(&sub.hl, size: sub.size, scale: scale)
    quantizeMid(&sub.lh, size: sub.size, scale: scale)
    quantizeHigh(&sub.hh, size: sub.size, scale: scale)
    
    // Write scale
    bw.data.append(UInt8(scale))
    
    let rw = RiceWriter(bw: bw)
    blockEncodeDPCM(rw: rw, block: sub.ll, size: sub.size)
    blockEncode(rw: rw, block: sub.hl, size: sub.size)
    blockEncode(rw: rw, block: sub.lh, size: sub.size)
    blockEncode(rw: rw, block: sub.hh, size: sub.size)
    rw.flush()
}

func transformLayerFunc(w: Int, h: Int, size: Int, scale: Int) throws -> (Data, Block2D) {
    let (rows, localScale) = scale.rows(w: w, h: h, size: size, baseShift: scale)
    
    // Need a fresh BitWriter for just this block
    let bw = BitWriter()
    var mutableRows = rows
    
    let ll = try transformLayer(bw: bw, data: &mutableRows, size: size, scale: scale)
    
    return (bw.data, ll)
}

func transformBaseFunc(w: Int, h: Int, size: Int, scale: Int) throws -> Data {
    let (rows, localScale) = scale.rows(w: w, h: h, size: size, baseShift: scale)
    
    let bw = BitWriter()
    var mutableRows = rows
    
    try transformBase(bw: bw, data: &mutableRows, size: size, scale: scale)
    
    let br = BitReader(data: bw.data)
    let planes = try invertBase(br: br, size: size)
    return bw.data
}

func encodeLayer(r: ImageReader, scale: Int, size: Int) throws -> (Data, Image16) {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []
    
    let dx = r.width
    let dy = r.height
    
    var sub = Image16(width: (dx / 2), height: (dy / 2))
    
    // Y
    for h in stride(from: 0, to: dy, by: size) {
        for w in stride(from: 0, to: dx, by: size) {
            let (data, ll) = try transformLayerFunc(w: w, h: h, size: size, scale: scale)
            bufY.append(data)
            
            sub.updateY(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
        }
    }
    
    // Cb
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let (data, ll) = try transformLayerFunc(w: w, h: h, size: size, scale: scale)
            bufCb.append(data)
            
            sub.updateCb(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
        }
    }
    
    // Cr
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let (data, ll) = try transformLayerFunc(w: w, h: h, size: size, scale: scale)
            bufCr.append(data)
            
            sub.updateCr(data: ll, startX: (w / 2), startY: (h / 2), size: (size / 2))
        }
    }
    
    var out = Data()
    withUnsafeBytes(of: UInt16(dx).bigEndian) { out.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt16(dy).bigEndian) { out.append(contentsOf: $0) }
    
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

func encodeBase(r: ImageReader, scaler: RateController, scaleVal: Int, size: Int) throws -> Data {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []
    
    let dx = r.width
    let dy = r.height
    
    // Y
    for h in stride(from: 0, to: dy, by: size) {
        for w in stride(from: 0, to: dx, by: size) {
            let data = try transformBaseFunc(w: w, h: h, size: size, scale: scale)
            bufY.append(data)
        }
    }
    
    // Cb
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let data = try transformBaseFunc(w: w, h: h, size: size, scale: scale)
            bufCb.append(data)
        }
    }
    
    // Cr
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            let data = try transformBaseFunc(w: w, h: h, size: size, scale: scale)
            bufCr.append(data)
        }
    }
    
    var out = Data()
    withUnsafeBytes(of: UInt16(dx).bigEndian) { out.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt16(dy).bigEndian) { out.append(contentsOf: $0) }
    
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
    let halfImg = img.Resize(0.5)

    let r = ImageReader(img: halfImg)
    let (_, sub2) = try encodeLayer(r: r, scale: 2, size: 32)

}

public func encode(img: YCbCrImage, maxbitrate: Int) throws -> Data {
    let baseScale = estimateBaseScale(img: img, targetBitrate: maxbitrate)


    let r2 = ImageReader(img: img)
    let (layer2, sub2) = try encodeLayer(r: r2, scale: scale, size: 32)
    
    let r1 = ImageReader(img: sub2.toYCbCr())
    let (layer1, sub1) = try encodeLayer(r: r1, scale: scale, size: 16)
    
    let r0 = ImageReader(img: sub1.toYCbCr())
    let layer0 = try encodeBase(r: r0, scale: scale, size: 8)
    
    var out = Data()
    
    withUnsafeBytes(of: UInt32(layer0.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer0)
    
    withUnsafeBytes(of: UInt32(layer1.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer1)
    
    withUnsafeBytes(of: UInt32(layer2.count).bigEndian) { out.append(contentsOf: $0) }
    out.append(layer2)
    
    return out
}
