import Foundation

// MARK: - Decode Logic

func blockDecode(rr: RiceReader, size: Int) throws -> [[Int16]] {
    var data = [[Int16]](repeating: [], count: size)
    for y in 0..<size {
        var tmp = [Int16](repeating: 0, count: size)
        for x in 0..<size {
            let v = try rr.read(k: k)
            tmp[x] = toInt16(v)
        }
        data[y] = tmp
    }
    return data
}

func invertLayer(br: BitReader, ll: [[Int16]], size: Int) throws -> [[Int16]] {
    let scaleU8 = try br.readBits(n: 8)
    let scale = Int(scaleU8)
    
    let rr = RiceReader(br: br)
    
    var hl = try blockDecode(rr: rr, size: (size / 2))
    var lh = try blockDecode(rr: rr, size: (size / 2))
    var hh = try blockDecode(rr: rr, size: (size / 2))
    
    dequantizeMid(&hl, size: (size / 2), scale: scale)
    dequantizeMid(&lh, size: (size / 2), scale: scale)
    dequantizeHigh(&hh, size: (size / 2), scale: scale)
    
    let sub = Subbands(ll: ll, hl: hl, lh: lh, hh: hh, size: (size / 2))
    return invDwt2d(sub)
}

func invertFull(br: BitReader, size: Int) throws -> [[Int16]] {
    let scaleU8 = try br.readBits(n: 8)
    let scale = Int(scaleU8)
    
    let rr = RiceReader(br: br)
    
    var ll = try blockDecode(rr: rr, size: (size / 2))
    var hl = try blockDecode(rr: rr, size: (size / 2))
    var lh = try blockDecode(rr: rr, size: (size / 2))
    var hh = try blockDecode(rr: rr, size: (size / 2))
    
    dequantizeLow(&ll, size: (size / 2), scale: scale)
    dequantizeMid(&hl, size: (size / 2), scale: scale)
    dequantizeMid(&lh, size: (size / 2), scale: scale)
    dequantizeHigh(&hh, size: (size / 2), scale: scale)
    
    let sub = Subbands(ll: ll, hl: hl, lh: lh, hh: hh, size: (size / 2))
    return invDwt2d(sub)
}

public typealias SetRowFunc = (_ x: Int, _ y: Int, _ size: Int, _ plane: [Int16], _ prediction: Int16) -> Void
public typealias GetLLFunc = (_ x: Int, _ y: Int, _ size: Int, _ prediction: Int16) -> [[Int16]]

func invertLayerFunc(br: BitReader, w: Int, h: Int, size: Int, predict: PredictFunc, setRow: SetRowFunc, getLL: GetLLFunc) throws -> ([[Int16]], Int16) {
    let prediction = predict(w, h, size)
    let ll = getLL(w/2, h/2, size/2, prediction)
    let planes = try invertLayer(br: br, ll: ll, size: size)
    
    for i in 0..<size {
        setRow(w, (h + i), size, planes[i], prediction)
    }
    return (planes, prediction)
}

func invertBaseFunc(br: BitReader, w: Int, h: Int, size: Int, predict: PredictFunc, setRow: SetRowFunc) throws -> ([[Int16]], Int16) {
    let prediction = predict(w, h, size)
    let planes = try invertFull(br: br, size: size)
    
    for i in 0..<size {
        setRow(w, (h + i), size, planes[i], prediction)
    }
    return (planes, prediction)
}

func decodeLayer(r: Data, prev: Image16, size: Int) throws -> Image16 {
    var offset = 0
    
    func readUInt16() throws -> UInt16 {
        guard (offset + 2) <= r.count else { throw NSError(domain: "DecodeError", code: 1, userInfo: nil) }
        let val = r.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        offset += 2
        return val
    }
    
    func readBlock() throws -> Data {
        let len = try readUInt16()
        guard (offset + Int(len)) <= r.count else { throw NSError(domain: "DecodeError", code: 2, userInfo: nil) }
        let data = r.subdata(in: offset..<(offset + Int(len)))
        offset += Int(len)
        return data
    }
    
    let dx = Int(try readUInt16())
    let dy = Int(try readUInt16())
    
    let bufYLen = Int(try readUInt16())
    var yBufs: [Data] = []
    for _ in 0..<bufYLen {
        yBufs.append(try readBlock())
    }
    
    let bufCbLen = Int(try readUInt16())
    var cbBufs: [Data] = []
    for _ in 0..<bufCbLen {
        cbBufs.append(try readBlock())
    }
    
    let bufCrLen = Int(try readUInt16())
    var crBufs: [Data] = []
    for _ in 0..<bufCrLen {
        crBufs.append(try readBlock())
    }
    
    var sub = Image16(width: dx, height: dy)
    let tmp = ImagePredictor(width: dx, height: dy)
    
    // Y
    for h in stride(from: 0, to: dy, by: size) {
        for w in stride(from: 0, to: dx, by: size) {
            guard yBufs.isEmpty != true else { throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Y block"]) }
            let data = yBufs.removeFirst()
            let br = BitReader(data: data)
            
            let (ll, prediction) = try invertLayerFunc(br: br, w: w, h: h, size: size, predict: tmp.predictY, setRow: tmp.updateY, getLL: prev.getY)
            sub.updateY(data: ll, prediction: prediction, startX: w, startY: h, size: size)
        }
    }
    
    // Cb
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
             guard cbBufs.isEmpty != true else { throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Cb block"]) }
            let data = cbBufs.removeFirst()
            let br = BitReader(data: data)
            
            let (ll, prediction) = try invertLayerFunc(br: br, w: w, h: h, size: size, predict: tmp.predictCb, setRow: tmp.updateCb, getLL: prev.getCb)
            sub.updateCb(data: ll, prediction: prediction, startX: w, startY: h, size: size)
        }
    }
    
    // Cr
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            guard crBufs.isEmpty != true else { throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Cr block"]) }
            let data = crBufs.removeFirst()
            let br = BitReader(data: data)
            
            let (ll, prediction) = try invertLayerFunc(br: br, w: w, h: h, size: size, predict: tmp.predictCr, setRow: tmp.updateCr, getLL: prev.getCr)
            sub.updateCr(data: ll, prediction: prediction, startX: w, startY: h, size: size)
        }
    }
    
    return sub
}

func decodeBase(r: Data, size: Int) throws -> Image16 {
    var offset = 0
    
    func readUInt16() throws -> UInt16 {
        guard (offset + 2) <= r.count else { throw NSError(domain: "DecodeError", code: 1, userInfo: nil) }
        let val = r.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        offset += 2
        return val
    }
    
    func readBlock() throws -> Data {
        let len = try readUInt16()
        guard (offset + Int(len)) <= r.count else { throw NSError(domain: "DecodeError", code: 2, userInfo: nil) }
        let data = r.subdata(in: offset..<(offset + Int(len)))
        offset += Int(len)
        return data
    }
    
    let dx = Int(try readUInt16())
    let dy = Int(try readUInt16())
    
    let bufYLen = Int(try readUInt16())
    var yBufs: [Data] = []
    for _ in 0..<bufYLen {
        yBufs.append(try readBlock())
    }
    
    let bufCbLen = Int(try readUInt16())
    var cbBufs: [Data] = []
    for _ in 0..<bufCbLen {
        cbBufs.append(try readBlock())
    }
    
    let bufCrLen = Int(try readUInt16())
    var crBufs: [Data] = []
    for _ in 0..<bufCrLen {
        crBufs.append(try readBlock())
    }
    
    var sub = Image16(width: dx, height: dy)
    let tmp = ImagePredictor(width: dx, height: dy)
    
    // Y
    for h in stride(from: 0, to: dy, by: size) {
        for w in stride(from: 0, to: dx, by: size) {
            guard yBufs.isEmpty != true else { throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Y block"]) }
            let data = yBufs.removeFirst()
            let br = BitReader(data: data)
            
            let (ll, prediction) = try invertBaseFunc(br: br, w: w, h: h, size: size, predict: tmp.predictY, setRow: tmp.updateY)
            sub.updateY(data: ll, prediction: prediction, startX: w, startY: h, size: size)
        }
    }
    
    // Cb
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
             guard cbBufs.isEmpty != true else { throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Cb block"]) }
            let data = cbBufs.removeFirst()
            let br = BitReader(data: data)
            
              let (ll, prediction) = try invertBaseFunc(br: br, w: w, h: h, size: size, predict: tmp.predictCb, setRow: tmp.updateCb)
            sub.updateCb(data: ll, prediction: prediction, startX: w, startY: h, size: size)
        }
    }
    
    // Cr
    for h in stride(from: 0, to: (dy / 2), by: size) {
        for w in stride(from: 0, to: (dx / 2), by: size) {
            guard crBufs.isEmpty != true else { throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Cr block"]) }
            let data = crBufs.removeFirst()
            let br = BitReader(data: data)
            
            let (ll, prediction) = try invertBaseFunc(br: br, w: w, h: h, size: size, predict: tmp.predictCr, setRow: tmp.updateCr)
            sub.updateCr(data: ll, prediction: prediction, startX: w, startY: h, size: size)
        }
    }
    
    return sub
}

public func decode(r: Data) throws -> (YCbCrImage, YCbCrImage, YCbCrImage) {
    var offset = 0
    
    func readUInt32() throws -> UInt32 {
        guard (offset + 4) <= r.count else { throw NSError(domain: "DecodeError", code: 1, userInfo: nil) }
        let val = r.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4
        return val
    }
    
    func readLayerData() throws -> Data {
        let len = try readUInt32()
        guard (offset + Int(len)) <= r.count else { throw NSError(domain: "DecodeError", code: 2, userInfo: nil) }
        let data = r.subdata(in: offset..<(offset + Int(len)))
        offset += Int(len)
        return data
    }
    
    let layer0Data = try readLayerData()
    let layer0 = try decodeBase(r: layer0Data, size: 8)
    
    let layer1Data = try readLayerData()
    let layer1 = try decodeLayer(r: layer1Data, prev: layer0, size: 16)
    
    let layer2Data = try readLayerData()
    let layer2 = try decodeLayer(r: layer2Data, prev: layer1, size: 32)
    
    return (layer0.toYCbCr(), layer1.toYCbCr(), layer2.toYCbCr())
}
