import Foundation

// MARK: - Decode Logic

func blockDecode(rr: RiceReader, size: Int) throws -> Block2D {
    let block = Block2D(width: size, height: size)
    try block.data.withUnsafeMutableBufferPointer { buf in
        guard var p = buf.baseAddress else { return }
        for _ in 0..<(size * size) {
            let v = try rr.read(k: k)
            p.pointee = Int16(bitPattern: v)
            p += 1
        }
    }
    return block
}

func blockDecodeDPCM(rr: RiceReader, size: Int) throws -> Block2D {
    let block = Block2D(width: size, height: size)
    var prevVal: Int16 = 0

    try block.data.withUnsafeMutableBufferPointer { buf in
        guard var p = buf.baseAddress else { return }
        for _ in 0..<(size * size) {
            let v = try rr.read(k: k)
            let diff = toInt16(v)

            let val = diff + prevVal
            p.pointee = val
            p += 1

            prevVal = val
        }
    }
    return block
}

func invertLayer(br: BitReader, ll: Block2D, size: Int, scale: Int) throws -> Block2D {
    let rr = RiceReader(br: br)
    
    var hl = try blockDecode(rr: rr, size: (size / 2))
    var lh = try blockDecode(rr: rr, size: (size / 2))
    var hh = try blockDecode(rr: rr, size: (size / 2))
    
    dequantizeMidSignedMapping(&hl, size: (size / 2), scale: scale)
    dequantizeMidSignedMapping(&lh, size: (size / 2), scale: scale)
    dequantizeHighSignedMapping(&hh, size: (size / 2), scale: scale)
    
    let sub = Subbands(ll: ll, hl: hl, lh: lh, hh: hh, size: (size / 2))
    return invDwt2d(sub)
}

func invertBase(br: BitReader, size: Int, scale: Int) throws -> Block2D {
    let rr = RiceReader(br: br)
    
    var ll = try blockDecodeDPCM(rr: rr, size: (size / 2))
    var hl = try blockDecode(rr: rr, size: (size / 2))
    var lh = try blockDecode(rr: rr, size: (size / 2))
    var hh = try blockDecode(rr: rr, size: (size / 2))
    
    dequantizeLow(&ll, size: (size / 2), scale: scale)
    dequantizeMidSignedMapping(&hl, size: (size / 2), scale: scale)
    dequantizeMidSignedMapping(&lh, size: (size / 2), scale: scale)
    dequantizeHighSignedMapping(&hh, size: (size / 2), scale: scale)
    
    let sub = Subbands(ll: ll, hl: hl, lh: lh, hh: hh, size: (size / 2))
    return invDwt2d(sub)
}

public typealias GetLLFunc = (_ x: Int, _ y: Int, _ size: Int) -> Block2D

func invertLayerFunc(br: BitReader, w: Int, h: Int, size: Int, scale: Int, getLL: GetLLFunc) throws -> Block2D {
    let ll = getLL(w/2, h/2, size/2)
    let planes = try invertLayer(br: br, ll: ll, size: size, scale: scale)
    return planes
}

func invertBaseFunc(br: BitReader, w: Int, h: Int, size: Int, scale: Int) throws -> Block2D {
    let planes = try invertBase(br: br, size: size, scale: scale)
    return planes
}

func decodeLayer(r: Data, prev: Image16, size: Int) async throws -> Image16 {
    var offset = 0
    
    func readUInt8() throws -> UInt8 {
        guard (offset + 1) <= r.count else { throw NSError(domain: "DecodeError", code: 1, userInfo: nil) }
        let val = r.subdata(in: offset..<(offset + 1)).withUnsafeBytes { $0.load(as: UInt8.self).bigEndian }
        offset += 1
        return val
    }
    
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
    let scale = Int(try readUInt8())
    
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
    
    // Y
    try await withThrowingTaskGroup(of: (Int, [(Block2D, Int, Int)]).self) { group in
        var bufIndex = 0
        for h in stride(from: 0, to: dy, by: size) {
            let wStride = Array(stride(from: 0, to: dx, by: size))
            let rowBufs = Array(yBufs[bufIndex..<(bufIndex + wStride.count)])
            bufIndex += wStride.count
            
            group.addTask {
                var rowResults: [(Block2D, Int, Int)] = []
                for (i, w) in wStride.enumerated() {
                    let data = rowBufs[i]
                    let br = BitReader(data: data)
                    let ll = try invertLayerFunc(br: br, w: w, h: h, size: size, scale: scale, getLL: prev.getY)
                    rowResults.append((ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (ll, w, h) in rowBlocks {
                sub.updateY(data: ll, startX: w, startY: h, size: size)
            }
        }
    }
    
    // Cb
    try await withThrowingTaskGroup(of: (Int, [(Block2D, Int, Int)]).self) { group in
        var bufIndex = 0
        for h in stride(from: 0, to: (dy / 2), by: size) {
            let wStride = Array(stride(from: 0, to: (dx / 2), by: size))
            let rowBufs = Array(cbBufs[bufIndex..<(bufIndex + wStride.count)])
            bufIndex += wStride.count
            
            group.addTask {
                var rowResults: [(Block2D, Int, Int)] = []
                for (i, w) in wStride.enumerated() {
                    let data = rowBufs[i]
                    let br = BitReader(data: data)
                    let ll = try invertLayerFunc(br: br, w: w, h: h, size: size, scale: scale, getLL: prev.getCb)
                    rowResults.append((ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (ll, w, h) in rowBlocks {
                sub.updateCb(data: ll, startX: w, startY: h, size: size)
            }
        }
    }
    
    // Cr
    try await withThrowingTaskGroup(of: (Int, [(Block2D, Int, Int)]).self) { group in
        var bufIndex = 0
        for h in stride(from: 0, to: (dy / 2), by: size) {
            let wStride = Array(stride(from: 0, to: (dx / 2), by: size))
            let rowBufs = Array(crBufs[bufIndex..<(bufIndex + wStride.count)])
            bufIndex += wStride.count
            
            group.addTask {
                var rowResults: [(Block2D, Int, Int)] = []
                for (i, w) in wStride.enumerated() {
                    let data = rowBufs[i]
                    let br = BitReader(data: data)
                    let ll = try invertLayerFunc(br: br, w: w, h: h, size: size, scale: scale, getLL: prev.getCr)
                    rowResults.append((ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (ll, w, h) in rowBlocks {
                sub.updateCr(data: ll, startX: w, startY: h, size: size)
            }
        }
    }
    
    return sub
}

func decodeBase(r: Data, size: Int) async throws -> Image16 {
    var offset = 0
    
    func readUInt8() throws -> UInt8 {
        guard (offset + 1) <= r.count else { throw NSError(domain: "DecodeError", code: 1, userInfo: nil) }
        let val = r.subdata(in: offset..<(offset + 1)).withUnsafeBytes { $0.load(as: UInt8.self).bigEndian }
        offset += 1
        return val
    }
    
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
    let scale = Int(try readUInt8())
    
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
    
    // Y
    try await withThrowingTaskGroup(of: (Int, [(Block2D, Int, Int)]).self) { group in
        var bufIndex = 0
        for h in stride(from: 0, to: dy, by: size) {
            let wStride = Array(stride(from: 0, to: dx, by: size))
            let rowBufs = Array(yBufs[bufIndex..<(bufIndex + wStride.count)])
            bufIndex += wStride.count
            
            group.addTask {
                var rowResults: [(Block2D, Int, Int)] = []
                for (i, w) in wStride.enumerated() {
                    let data = rowBufs[i]
                    let br = BitReader(data: data)
                    let ll = try invertBaseFunc(br: br, w: w, h: h, size: size, scale: scale)
                    rowResults.append((ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (ll, w, h) in rowBlocks {
                sub.updateY(data: ll, startX: w, startY: h, size: size)
            }
        }
    }
    
    // Cb
    try await withThrowingTaskGroup(of: (Int, [(Block2D, Int, Int)]).self) { group in
        var bufIndex = 0
        for h in stride(from: 0, to: (dy / 2), by: size) {
            let wStride = Array(stride(from: 0, to: (dx / 2), by: size))
            let rowBufs = Array(cbBufs[bufIndex..<(bufIndex + wStride.count)])
            bufIndex += wStride.count
            
            group.addTask {
                var rowResults: [(Block2D, Int, Int)] = []
                for (i, w) in wStride.enumerated() {
                    let data = rowBufs[i]
                    let br = BitReader(data: data)
                    let ll = try invertBaseFunc(br: br, w: w, h: h, size: size, scale: scale)
                    rowResults.append((ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (ll, w, h) in rowBlocks {
                sub.updateCb(data: ll, startX: w, startY: h, size: size)
            }
        }
    }
    
    // Cr
    try await withThrowingTaskGroup(of: (Int, [(Block2D, Int, Int)]).self) { group in
        var bufIndex = 0
        for h in stride(from: 0, to: (dy / 2), by: size) {
            let wStride = Array(stride(from: 0, to: (dx / 2), by: size))
            let rowBufs = Array(crBufs[bufIndex..<(bufIndex + wStride.count)])
            bufIndex += wStride.count
            
            group.addTask {
                var rowResults: [(Block2D, Int, Int)] = []
                for (i, w) in wStride.enumerated() {
                    let data = rowBufs[i]
                    let br = BitReader(data: data)
                    let ll = try invertBaseFunc(br: br, w: w, h: h, size: size, scale: scale)
                    rowResults.append((ll, w, h))
                }
                return (h, rowResults)
            }
        }
        
        var results: [(Int, [(Block2D, Int, Int)])] = []
        for try await res in group {
            results.append(res)
        }
        results.sort { $0.0 < $1.0 }
        
        for (_, rowBlocks) in results {
            for (ll, w, h) in rowBlocks {
                sub.updateCr(data: ll, startX: w, startY: h, size: size)
            }
        }
    }
    
    return sub
}

public func decode(r: Data) async throws -> (YCbCrImage, YCbCrImage, YCbCrImage) {
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
    let layer0 = try await decodeBase(r: layer0Data, size: 8)
    
    let layer1Data = try readLayerData()
    let layer1 = try await decodeLayer(r: layer1Data, prev: layer0, size: 16)
    
    let layer2Data = try readLayerData()
    let layer2 = try await decodeLayer(r: layer2Data, prev: layer1, size: 32)
    
    return (layer0.toYCbCr(), layer1.toYCbCr(), layer2.toYCbCr())
}

public func decodeLayers(data: Data...) async throws -> YCbCrImage {
    guard let base = data.first else {
        throw NSError(domain: "DecodeError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data provided"])
    }
    
    var current = try await decodeBase(r: base, size: 8)
    var currentSize = 16
    
    for i in 1..<data.count {
        current = try await decodeLayer(r: data[i], prev: current, size: currentSize)
        currentSize *= 2
    }
    
    return current.toYCbCr()
}

public func decodeOne(r: Data) async throws -> YCbCrImage {
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
    
    let layerOneData = try readLayerData()
    let layerOne = try await decodeBase(r: layerOneData, size: 32)
    
    return layerOne.toYCbCr()
}