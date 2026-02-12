
// MARK: - Quantization

public func quantizeLow(_ block: inout [[Int16]], size: Int, scale: Int) {
    quantize(&block, size: size, scale: (scale + 2))
}

public func quantizeMid(_ block: inout [[Int16]], size: Int, scale: Int) {
    quantize(&block, size: size, scale: (scale + 3))
}

public func quantizeHigh(_ block: inout [[Int16]], size: Int, scale: Int) {
    quantize(&block, size: size, scale: (scale + 5))
}

private func quantize(_ data: inout [[Int16]], size: Int, scale: Int) {
    for y in 0..<size {
        for x in 0..<size {
            let v = Int32(data[y][x])
            let off = Int32(1 << (scale - 1))
            if 0 <= v {
                data[y][x] = Int16((v + off) >> scale)
            } else {
                data[y][x] = Int16(-1 * ((-1 * v + off) >> scale))
            }
        }
    }
}

// MARK: - Dequantization

public func dequantizeLow(_ block: inout [[Int16]], size: Int, scale: Int) {
    dequantize(&block, size: size, scale: (scale + 2))
}

public func dequantizeMid(_ block: inout [[Int16]], size: Int, scale: Int) {
    dequantize(&block, size: size, scale: (scale + 3))
}

public func dequantizeHigh(_ block: inout [[Int16]], size: Int, scale: Int) {
    dequantize(&block, size: size, scale: (scale + 5))
}

private func dequantize(_ data: inout [[Int16]], size: Int, scale: Int) {
    for y in 0..<size {
        for x in 0..<size {
            data[y][x] = (data[y][x] &<< scale)
        }
    }
}
