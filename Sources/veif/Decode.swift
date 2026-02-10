import Foundation

func decodeSubband(
    inData: [Data],
    plane: inout [Int16],
    width: Int,
    height: Int,
    startX: Int,
    startY: Int,
    endX: Int,
    endY: Int
) throws -> [Data] {
    let blockSize = EncBlockSize
    var currentInData = inData

    for y in stride(from: startY, to: endY, by: blockSize) {
        for x in stride(from: startX, to: endX, by: blockSize) {
            if currentInData.isEmpty {
                throw BitError.eoF  // Not enough blocks
            }
            let blockData = currentInData.removeFirst()
            let reader = BitReader(data: blockData)

            // Read scale
            let scale = try reader.readBits(n: 8)

            let rr = RiceReader<UInt16>(br: reader)
            let zigzagData = try blockRLEDecode(rr: rr, size: blockSize * blockSize)

            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            block.withUnsafeMutableBufferPointer { blockPtr in
                zigzagData.withUnsafeBufferPointer { zigzagUIntPtr in
                    let zigzagIntPtr = UnsafeBufferPointer(
                        start: UnsafePointer<Int16>(OpaquePointer(zigzagUIntPtr.baseAddress)),
                        count: zigzagUIntPtr.count
                    )

                    unzigzag(data: zigzagIntPtr, size: blockSize, into: blockPtr)
                }

                dequantizeBlock(block: blockPtr, size: blockSize, scale: Int(scale))
            }

            // Copy to plane
            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    if px < width && py < height {
                        plane[py * width + px] = block[i * blockSize + j]
                    }
                }
            }
        }
    }
    return currentInData
}

func decodeLayer(data: Data, prevImg: Image16) throws -> Image16 {
    let br = BinaryReader(data: data)

    let dx = Int(try br.read(as: UInt16.self))
    let dy = Int(try br.read(as: UInt16.self))

    let ySize = Int(try br.read(as: UInt32.self))
    var yBufs: [Data] = []

    // The wrapping while loop logic:
    var i = 0
    // Reset yBufs
    yBufs = []
    while i < ySize {
        let blockLen = Int(try br.read(as: UInt16.self))
        let buf = br.readBytes(blockLen)
        yBufs.append(buf)
        i += blockLen
    }

    let cbSize = Int(try br.read(as: UInt32.self))
    var cbBufs: [Data] = []
    i = 0
    while i < cbSize {
        let blockLen = Int(try br.read(as: UInt16.self))
        let buf = br.readBytes(blockLen)
        cbBufs.append(buf)
        i += blockLen
    }

    let crSize = Int(try br.read(as: UInt32.self))
    var crBufs: [Data] = []
    i = 0
    while i < crSize {
        let blockLen = Int(try br.read(as: UInt16.self))
        let buf = br.readBytes(blockLen)
        crBufs.append(buf)
        i += blockLen
    }

    // Skip sequence numbers
    if br.offset < br.data.count {
        let mbYSize = Int(try br.read(as: UInt32.self))
        br.seek(to: br.offset + mbYSize)
    }
    if br.offset < br.data.count {
        let mbCbSize = Int(try br.read(as: UInt32.self))
        br.seek(to: br.offset + mbCbSize)
    }
    if br.offset < br.data.count {
        let mbCrSize = Int(try br.read(as: UInt32.self))
        br.seek(to: br.offset + mbCrSize)
    }

    // Decode
    let currentImg = Image16(width: dx, height: dy)
    let w = dx
    let h = dy
    let nextW = w / 2
    let nextH = h / 2

    // Copy LL from prevImg
    for y in 0..<nextH {
        for x in 0..<nextW {
            let py = if prevImg.height <= y { prevImg.height - 1 } else { y }
            let px = if prevImg.width <= x { prevImg.width - 1 } else { x }

            currentImg.yPlane[currentImg.yOffset(x: x, y: y)] = prevImg.yPlane[prevImg.yOffset(x: px, y: py)]
        }
    }

    // Decode HL, LH, HH
    yBufs = try decodeSubband(
        inData: yBufs,
        plane: &currentImg.yPlane,
        width: w,
        height: h,
        startX: nextW,
        startY: 0,
        endX: w,
        endY: nextH
    )
    yBufs = try decodeSubband(
        inData: yBufs,
        plane: &currentImg.yPlane,
        width: w,
        height: h,
        startX: 0,
        startY: nextH,
        endX: nextW,
        endY: h
    )
    yBufs = try decodeSubband(
        inData: yBufs,
        plane: &currentImg.yPlane,
        width: w,
        height: h,
        startX: nextW,
        startY: nextH,
        endX: w,
        endY: h
    )

    invDwtPlane(data: &currentImg.yPlane, width: w, height: h)

    // Chroma
    let cw = w / 2
    let ch = h / 2
    let nextCW = cw / 2
    let nextCH = ch / 2

    // Cb
    for y in 0..<nextCH {
        for x in 0..<nextCW {
            let py = if prevImg.height / 2 <= y { prevImg.height / 2 - 1 } else { y }
            let px = if prevImg.width / 2 <= x { prevImg.width / 2 - 1 } else { x }
            currentImg.cbPlane[currentImg.cOffset(x: x, y: y)] = prevImg.cbPlane[prevImg.cOffset(x: px, y: py)]
        }
    }
    cbBufs = try decodeSubband(
        inData: cbBufs,
        plane: &currentImg.cbPlane,
        width: cw,
        height: ch,
        startX: nextCW,
        startY: 0,
        endX: cw,
        endY: nextCH
    )
    cbBufs = try decodeSubband(
        inData: cbBufs,
        plane: &currentImg.cbPlane,
        width: cw,
        height: ch,
        startX: 0,
        startY: nextCH,
        endX: nextCW,
        endY: ch
    )
    cbBufs = try decodeSubband(
        inData: cbBufs,
        plane: &currentImg.cbPlane,
        width: cw,
        height: ch,
        startX: nextCW,
        startY: nextCH,
        endX: cw,
        endY: ch
    )
    invDwtPlane(data: &currentImg.cbPlane, width: cw, height: ch)

    // Cr
    for y in 0..<nextCH {
        for x in 0..<nextCW {
            var py = y
            if prevImg.height / 2 <= py { py = prevImg.height / 2 - 1 }
            var px = x
            if prevImg.width / 2 <= px { px = prevImg.width / 2 - 1 }
            currentImg.crPlane[currentImg.cOffset(x: x, y: y)] = prevImg.crPlane[prevImg.cOffset(x: px, y: py)]
        }
    }
    crBufs = try decodeSubband(
        inData: crBufs,
        plane: &currentImg.crPlane,
        width: cw,
        height: ch,
        startX: nextCW,
        startY: 0,
        endX: cw,
        endY: nextCH
    )
    crBufs = try decodeSubband(
        inData: crBufs,
        plane: &currentImg.crPlane,
        width: cw,
        height: ch,
        startX: 0,
        startY: nextCH,
        endX: nextCW,
        endY: ch
    )
    crBufs = try decodeSubband(
        inData: crBufs,
        plane: &currentImg.crPlane,
        width: cw,
        height: ch,
        startX: nextCW,
        startY: nextCH,
        endX: cw,
        endY: ch
    )
    invDwtPlane(data: &currentImg.crPlane, width: cw, height: ch)

    return currentImg
}

func decodeBase(data: Data) throws -> Image16 {
    let br = BinaryReader(data: data)

    let dx = Int(try br.read(as: UInt16.self))
    let dy = Int(try br.read(as: UInt16.self))

    let ySize = Int(try br.read(as: UInt32.self))
    var yBufs: [Data] = []
    var i = 0
    while i < ySize {
        let blockLen = Int(try br.read(as: UInt16.self))
        yBufs.append(br.readBytes(blockLen))
        i += blockLen
    }

    let cbSize = Int(try br.read(as: UInt32.self))
    var cbBufs: [Data] = []
    i = 0
    while i < cbSize {
        let blockLen = Int(try br.read(as: UInt16.self))
        cbBufs.append(br.readBytes(blockLen))
        i += blockLen
    }

    let crSize = Int(try br.read(as: UInt32.self))
    var crBufs: [Data] = []
    i = 0
    while i < crSize {
        let blockLen = Int(try br.read(as: UInt16.self))
        crBufs.append(br.readBytes(blockLen))
        i += blockLen
    }

    let currentImg = Image16(width: dx, height: dy)
    let blockSize = EncBlockSize

    // Decode Y
    for y in stride(from: 0, to: dy, by: blockSize) {
        for x in stride(from: 0, to: dx, by: blockSize) {
            if yBufs.isEmpty { throw BitError.eoF }
            let blockData = yBufs.removeFirst()
            let reader = BitReader(data: blockData)

            let scale = try reader.readBits(n: 8)
            let rr = RiceReader<UInt16>(br: reader)
            let zigzagData = try blockRLEDecode(rr: rr, size: blockSize * blockSize)

            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            block.withUnsafeMutableBufferPointer { blockPtr in
                zigzagData.withUnsafeBufferPointer { zigzagUIntPtr in
                    let zigzagIntPtr = UnsafeBufferPointer(
                        start: UnsafePointer<Int16>(OpaquePointer(zigzagUIntPtr.baseAddress)),
                        count: zigzagUIntPtr.count
                    )
                    unzigzag(data: zigzagIntPtr, size: blockSize, into: blockPtr)
                }
                dequantizeBlock(block: blockPtr, size: blockSize, scale: Int(scale))
                if let ptr = blockPtr.baseAddress {
                    invDwtBlock2Level(data: ptr, size: blockSize)
                }
            }

            // Copy to plane
            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    if px < dx && py < dy {
                        currentImg.yPlane[py * dx + px] = block[i * blockSize + j]
                    }
                }
            }
        }
    }

    // Decode Chroma
    let cw = dx / 2
    let ch = dy / 2

    // Cb
    for y in stride(from: 0, to: ch, by: blockSize) {
        for x in stride(from: 0, to: cw, by: blockSize) {
            if cbBufs.isEmpty { throw BitError.eoF }
            let blockData = cbBufs.removeFirst()
            let reader = BitReader(data: blockData)

            let scale = try reader.readBits(n: 8)
            let rr = RiceReader<UInt16>(br: reader)
            let zigzagData = try blockRLEDecode(rr: rr, size: blockSize * blockSize)

            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            block.withUnsafeMutableBufferPointer { blockPtr in
                zigzagData.withUnsafeBufferPointer { zigzagUIntPtr in
                    let zigzagIntPtr = UnsafeBufferPointer(
                        start: UnsafePointer<Int16>(OpaquePointer(zigzagUIntPtr.baseAddress)),
                        count: zigzagUIntPtr.count
                    )
                    unzigzag(data: zigzagIntPtr, size: blockSize, into: blockPtr)
                }
                dequantizeBlock(block: blockPtr, size: blockSize, scale: Int(scale))
                if let ptr = blockPtr.baseAddress {
                    invDwtBlock2Level(data: ptr, size: blockSize)
                }
            }

            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    if px < cw && py < ch {
                        currentImg.cbPlane[py * cw + px] = block[i * blockSize + j]
                    }
                }
            }
        }
    }

    // Cr
    for y in stride(from: 0, to: ch, by: blockSize) {
        for x in stride(from: 0, to: cw, by: blockSize) {
            if crBufs.isEmpty { throw BitError.eoF }
            let blockData = crBufs.removeFirst()
            let reader = BitReader(data: blockData)

            let scale = try reader.readBits(n: 8)
            let rr = RiceReader<UInt16>(br: reader)
            let zigzagData = try blockRLEDecode(rr: rr, size: blockSize * blockSize)

            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            block.withUnsafeMutableBufferPointer { blockPtr in
                zigzagData.withUnsafeBufferPointer { zigzagUIntPtr in
                    let zigzagIntPtr = UnsafeBufferPointer(
                        start: UnsafePointer<Int16>(OpaquePointer(zigzagUIntPtr.baseAddress)),
                        count: zigzagUIntPtr.count
                    )
                    unzigzag(data: zigzagIntPtr, size: blockSize, into: blockPtr)
                }
                dequantizeBlock(block: blockPtr, size: blockSize, scale: Int(scale))
                if let ptr = blockPtr.baseAddress {
                    invDwtBlock2Level(data: ptr, size: blockSize)
                }
            }

            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    if px < cw && py < ch {
                        currentImg.crPlane[py * cw + px] = block[i * blockSize + j]
                    }
                }
            }
        }
    }

    return currentImg
}

public func decode(layers: [Data]) throws -> Image16 {
    if layers.isEmpty {
        return Image16(width: 0, height: 0)  // Error?
    }

    let baseImg = try decodeBase(data: layers[0])

    if layers.count == 1 {
        return baseImg
    }

    let layer1Img = try decodeLayer(data: layers[1], prevImg: baseImg)

    if layers.count == 2 {
        return layer1Img
    }

    let layer2Img = try decodeLayer(data: layers[2], prevImg: layer1Img)

    return layer2Img
}
