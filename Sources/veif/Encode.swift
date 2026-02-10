import Foundation

let EncBlockSize = 16

func transformBlockData(out: BitWriter, data: UnsafeMutablePointer<Int16>, size: Int, scale: Int) {
    // Write scale (uint8)
    out.writeByte(UInt8(scale))

    quantizeBlock(block: data, size: size, scale: scale)

    var u16data = [UInt16](repeating: 0, count: size * size)
    u16data.withUnsafeMutableBufferPointer { u16Bp in
        let i16Bp = UnsafeMutableBufferPointer(
            start: UnsafeMutablePointer<Int16>(OpaquePointer(u16Bp.baseAddress)),
            count: u16Bp.count
        )

        let srcBp = UnsafeBufferPointer(start: data, count: size * size)
        zigzag(data: srcBp, size: size, into: i16Bp)
    }

    let rw = RiceWriter<UInt16>(bw: out)
    blockRLEEncode(rw: rw, data: u16data)
    rw.flush()
}

func encodeSubband(
    plane: [Int16], width: Int, height: Int, startX: Int, startY: Int, endX: Int, endY: Int,
    scaler: RateController
) -> [Data] {
    var out: [Data] = []
    let blockSize = EncBlockSize
    var scaleVal = 1

    for y in stride(from: startY, to: endY, by: blockSize) {
        for x in stride(from: startX, to: endX, by: blockSize) {
            // Extract block
            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    var val: Int16 = 0
                    if px < width && py < height {
                        val = plane[py * width + px]
                    }
                    block[i * blockSize + j] = val
                }
            }

            // Encode block
            let bw = BitWriter()
            block.withUnsafeMutableBufferPointer { bp in
                transformBlockData(out: bw, data: bp.baseAddress!, size: blockSize, scale: scaleVal)
            }

            let data = bw.data
            out.append(data)

            scaleVal = scaler.calcScale(addedBits: data.count * 8, addedPixels: blockSize * blockSize)
        }
    }
    return out
}

func encodeLayer(src: Image16, maxbitrate: Int) -> (Data, Image16) {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []

    let dx = src.width
    let dy = src.height

    // DWT Y
    dwtPlane(data: &src.yPlane, width: dx, height: dy)

    let nextW = dx / 2
    let nextH = dy / 2
    let nextImg = Image16(width: nextW, height: nextH)

    // Copy LL to nextImg
    for y in 0..<nextH {
        for x in 0..<nextW {
            nextImg.yPlane[nextImg.yOffset(x: x, y: y)] = src.yPlane[y * dx + x]
        }
    }

    let scalerY = RateController(maxbit: maxbitrate, width: dx, height: dy)

    // Encode HL, LH, HH
    bufY.append(contentsOf: encodeSubband(
        plane: src.yPlane, width: dx, height: dy, startX: nextW, startY: 0, endX: dx,
        endY: nextH, scaler: scalerY
    ))
    bufY.append(contentsOf: encodeSubband(
        plane: src.yPlane, width: dx, height: dy, startX: 0, startY: nextH, endX: nextW,
        endY: dy, scaler: scalerY
    ))
    bufY.append(contentsOf: encodeSubband(
        plane: src.yPlane, width: dx, height: dy, startX: nextW, startY: nextH, endX: dx,
        endY: dy, scaler: scalerY
    ))

    // Chroma DWT
    let cw = dx / 2
    let ch = dy / 2
    dwtPlane(data: &src.cbPlane, width: cw, height: ch)
    dwtPlane(data: &src.crPlane, width: cw, height: ch)

    let nextCW = cw / 2
    let nextCH = ch / 2
    for y in 0..<nextCH {
        for x in 0..<nextCW {
            nextImg.cbPlane[nextImg.cOffset(x: x, y: y)] = src.cbPlane[y * cw + x]
            nextImg.crPlane[nextImg.cOffset(x: x, y: y)] = src.crPlane[y * cw + x]
        }
    }

    // Encode Chroma
    bufCb.append(contentsOf: encodeSubband(
        plane: src.cbPlane, width: cw, height: ch, startX: nextCW, startY: 0, endX: cw,
        endY: nextCH, scaler: scalerY
    ))
    bufCb.append(contentsOf: encodeSubband(
        plane: src.cbPlane, width: cw, height: ch, startX: 0, startY: nextCH, endX: nextCW,
        endY: ch, scaler: scalerY
    ))
    bufCb.append(contentsOf: encodeSubband(
        plane: src.cbPlane, width: cw, height: ch, startX: nextCW, startY: nextCH, endX: cw,
        endY: ch, scaler: scalerY
    ))
    bufCr.append(contentsOf: encodeSubband(
        plane: src.crPlane, width: cw, height: ch, startX: nextCW, startY: 0, endX: cw,
        endY: nextCH, scaler: scalerY
    ))
    bufCr.append(contentsOf: encodeSubband(
        plane: src.crPlane, width: cw, height: ch, startX: 0, startY: nextCH, endX: nextCW,
        endY: ch, scaler: scalerY
    ))
    bufCr.append(contentsOf: encodeSubband(
        plane: src.crPlane, width: cw, height: ch, startX: nextCW, startY: nextCH, endX: cw,
        endY: ch, scaler: scalerY
    ))

    let out = serializeStreams(
        dx: dx, dy: dy, bufY: bufY, bufCb: bufCb, bufCr: bufCr, mbYSeq: nil, mbCbSeq: nil,
        mbCrSeq: nil
    )
    return (out, nextImg)
}

func encodeBase(img: Image16, maxbitrate: Int) -> Data {
    var bufY: [Data] = []
    var bufCb: [Data] = []
    var bufCr: [Data] = []

    let dx = img.width
    let dy = img.height

    let scaler = RateController(maxbit: maxbitrate, width: dx, height: dy)
    var scaleVal = 1

    let blockSize = EncBlockSize

    // Encode Y
    for y in stride(from: 0, to: dy, by: blockSize) {
        for x in stride(from: 0, to: dx, by: blockSize) {
            // Extract block
            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    var val: Int16 = 0
                    if px < dx && py < dy {
                        val = img.yPlane[py * dx + px]
                    }
                    block[i * blockSize + j] = val
                }
            }

            // DWT
            block.withUnsafeMutableBufferPointer { bp in
                if let ptr = bp.baseAddress {
                    dwtBlock2Level(data: ptr, size: blockSize)
                }
            }

            // Encode
            let bw = BitWriter()
            block.withUnsafeMutableBufferPointer { bp in
                transformBlockData(out: bw, data: bp.baseAddress!, size: blockSize, scale: scaleVal)
            }
            let data = bw.data
            bufY.append(data)
            scaleVal = scaler.calcScale(addedBits: data.count * 8, addedPixels: blockSize * blockSize)
        }
    }

    // Encode Chroma
    let cw = dx / 2
    let ch = dy / 2

    // Cb
    for y in stride(from: 0, to: ch, by: blockSize) {
        for x in stride(from: 0, to: cw, by: blockSize) {
            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    var val: Int16 = 0
                    if px < cw && py < ch {
                        val = img.cbPlane[py * cw + px]
                    }
                    block[i * blockSize + j] = val
                }
            }
            block.withUnsafeMutableBufferPointer { bp in
                if let ptr = bp.baseAddress {
                    dwtBlock2Level(data: ptr, size: blockSize)
                }
            }
            let bw = BitWriter()
            block.withUnsafeMutableBufferPointer { bp in
                transformBlockData(out: bw, data: bp.baseAddress!, size: blockSize, scale: scaleVal)
            }
            let data = bw.data
            bufCb.append(data)
            scaleVal = scaler.calcScale(addedBits: data.count * 8, addedPixels: blockSize * blockSize)
        }
    }

    // Cr
    for y in stride(from: 0, to: ch, by: blockSize) {
        for x in stride(from: 0, to: cw, by: blockSize) {
            var block = [Int16](repeating: 0, count: blockSize * blockSize)
            for i in 0..<blockSize {
                for j in 0..<blockSize {
                    let px = x + j
                    let py = y + i
                    var val: Int16 = 0
                    if px < cw && py < ch {
                        val = img.crPlane[py * cw + px]
                    }
                    block[i * blockSize + j] = val
                }
            }
            block.withUnsafeMutableBufferPointer { bp in
                if let ptr = bp.baseAddress {
                    dwtBlock2Level(data: ptr, size: blockSize)
                }
            }
            let bw = BitWriter()
            block.withUnsafeMutableBufferPointer { bp in
                transformBlockData(out: bw, data: bp.baseAddress!, size: blockSize, scale: scaleVal)
            }
            let data = bw.data
            bufCr.append(data)
            scaleVal = scaler.calcScale(addedBits: data.count * 8, addedPixels: blockSize * blockSize)
        }
    }

    return serializeStreams(
        dx: dx, dy: dy, bufY: bufY, bufCb: bufCb, bufCr: bufCr, mbYSeq: nil, mbCbSeq: nil,
        mbCrSeq: nil
    )
}

func serializeStreams(
    dx: Int, dy: Int, bufY: [Data], bufCb: [Data], bufCr: [Data], mbYSeq: [UInt8]?,
    mbCbSeq: [UInt8]?, mbCrSeq: [UInt8]?
) -> Data {
    let bw = BinaryWriter()

    bw.write(UInt16(dx))
    bw.write(UInt16(dy))

    let ySize = bufY.reduce(0) { $0 + $1.count }
    bw.write(UInt32(ySize))
    for b in bufY {
        bw.write(UInt16(b.count))
        bw.append(b)
    }

    let cbSize = bufCb.reduce(0) { $0 + $1.count }
    bw.write(UInt32(cbSize))
    for b in bufCb {
        bw.write(UInt16(b.count))
        bw.append(b)
    }

    let crSize = bufCr.reduce(0) { $0 + $1.count }
    bw.write(UInt32(crSize))
    for b in bufCr {
        bw.write(UInt16(b.count))
        bw.append(b)
    }

    if let seq = mbYSeq {
        bw.write(UInt32(seq.count))
        bw.append(contentsOf: seq)
    }
    if let seq = mbCbSeq {
        bw.write(UInt32(seq.count))
        bw.append(contentsOf: seq)
    }
    if let seq = mbCrSeq {
        bw.write(UInt32(seq.count))
        bw.append(contentsOf: seq)
    }

    return bw.data
}

public func encode(img: Image16, maxbitrate: Int) -> (Data, Data, Data) {
    let (layer2, nextImg) = encodeLayer(src: img, maxbitrate: maxbitrate)
    let (layer1, nextImg2) = encodeLayer(src: nextImg, maxbitrate: maxbitrate)

    let layer0 = encodeBase(img: nextImg2, maxbitrate: maxbitrate)

    return (layer0, layer1, layer2)
}
