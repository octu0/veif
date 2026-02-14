
// MARK: - Quantization

let quantizeLowOffset = 0
let quantizeMidOffset = 1
let quantizeHighOffset = 3

public func quantizeLow(_ block: inout Block2D, size: Int, scale: Int) {
    quantize(&block, size: size, scale: (scale + quantizeLowOffset))
}

public func quantizeLowSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    quantizeSignedMapping(&block, size: size, scale: (scale + quantizeLowOffset))
}

public func quantizeMid(_ block: inout Block2D, size: Int, scale: Int) {
    quantize(&block, size: size, scale: (scale + quantizeMidOffset))
}

public func quantizeMidSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    quantizeSignedMapping(&block, size: size, scale: (scale + quantizeMidOffset))
}

public func quantizeHigh(_ block: inout Block2D, size: Int, scale: Int) {
    quantize(&block, size: size, scale: (scale + quantizeHighOffset))
}

public func quantizeHighSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    quantizeSignedMapping(&block, size: size, scale: (scale + quantizeHighOffset))
}

private func quantize(_ block: inout Block2D, size: Int, scale: Int) {
    #if arch(arm64) || arch(x86_64)
    let total = (size * size)
    switch total {
    case 16:
        quantizeSIMD4(&block, scale: scale)
    case 64:
        quantizeSIMD8(&block, scale: scale)
    case 256:
        quantizeSIMD16(&block, scale: scale)
    case 1024:
        quantizeSIMD32(&block, scale: scale)
    default:
        quantizeScalar(&block, size: size, scale: scale)
    }
    #else
    quantizeScalar(&block, size: size, scale: scale)
    #endif
}

private func quantizeSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    #if arch(arm64) || arch(x86_64)
    let total = (size * size)
    switch total {
    case 16:
        quantizeSIMD4SignedMapping(&block, scale: scale)
    case 64:
        quantizeSIMD8SignedMapping(&block, scale: scale)
    case 256:
        quantizeSIMD16SignedMapping(&block, scale: scale)
    case 1024:
        quantizeSIMD32SignedMapping(&block, scale: scale)
    default:
        quantizeScalarSignedMapping(&block, size: size, scale: scale)
    }
    #else
    quantizeScalarSignedMapping(&block, size: size, scale: scale)
    #endif
}

// MARK: - Quantization SIMD

#if arch(arm64) || arch(x86_64)

private func quantizeSIMD4(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD4<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD4<Int16>(repeating: Int16(scale))
    let zero = SIMD4<Int16>.zero
    let negOne = SIMD4<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 4) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD4<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD4<Int16>.self)
        }
    }
}

private func quantizeSIMD4SignedMapping(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD4<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD4<Int16>(repeating: Int16(scale))
    let zero = SIMD4<Int16>.zero
    let negOne = SIMD4<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 4) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD4<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            quantized = (quantized &<< 1) ^ (quantized &>> 15)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD4<Int16>.self)
        }
    }
}

private func quantizeSIMD8(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD8<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD8<Int16>(repeating: Int16(scale))
    let zero = SIMD8<Int16>.zero
    let negOne = SIMD8<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 8) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD8<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD8<Int16>.self)
        }
    }
}

private func quantizeSIMD8SignedMapping(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD8<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD8<Int16>(repeating: Int16(scale))
    let zero = SIMD8<Int16>.zero
    let negOne = SIMD8<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 8) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD8<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            quantized = (quantized &<< 1) ^ (quantized &>> 15)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD8<Int16>.self)
        }
    }
}

private func quantizeSIMD16(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD16<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD16<Int16>(repeating: Int16(scale))
    let zero = SIMD16<Int16>.zero
    let negOne = SIMD16<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 16) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD16<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD16<Int16>.self)
        }
    }
}

private func quantizeSIMD16SignedMapping(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD16<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD16<Int16>(repeating: Int16(scale))
    let zero = SIMD16<Int16>.zero
    let negOne = SIMD16<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 16) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD16<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            quantized = (quantized &<< 1) ^ (quantized &>> 15)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD16<Int16>.self)
        }
    }
}

private func quantizeSIMD32(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD32<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD32<Int16>(repeating: Int16(scale))
    let zero = SIMD32<Int16>.zero
    let negOne = SIMD32<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 32) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD32<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD32<Int16>.self)
        }
    }
}

private func quantizeSIMD32SignedMapping(_ block: inout Block2D, scale: Int) {
    let offVec = SIMD32<Int16>(repeating: Int16(1 << (scale - 1)))
    let scaleVec = SIMD32<Int16>(repeating: Int16(scale))
    let zero = SIMD32<Int16>.zero
    let negOne = SIMD32<Int16>(repeating: -1)

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 32) {
            let p = base.advanced(by: i)
            let vec = UnsafeRawPointer(p).load(as: SIMD32<Int16>.self)
            let isNeg = vec .< zero
            let absVec = vec.replacing(with: negOne &* vec, where: isNeg)
            var quantized = (absVec &+ offVec) &>> scaleVec
            quantized = quantized.replacing(with: negOne &* quantized, where: isNeg)
            quantized = (quantized &<< 1) ^ (quantized &>> 15)
            
            UnsafeMutableRawPointer(p).storeBytes(of: quantized, as: SIMD32<Int16>.self)
        }
    }
}

#endif  // arch(arm64) || arch(x86_64)

// MARK: - Quantization Scalar (fallback)

private func quantizeScalar(_ block: inout Block2D, size: Int, scale: Int) {
    let total = (size * size)
    for i in 0..<total {
        let v = Int32(block.data[i])
        let off = Int32(1 << (scale - 1))
        var q: Int16
        if 0 <= v {
            q = Int16((v + off) >> scale)
        } else {
            q = Int16(-1 * ((-1 * v + off) >> scale))
        }
        
        block.data[i] = q
    }
}

private func quantizeScalarSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    let total = (size * size)
    for i in 0..<total {
        let v = Int32(block.data[i])
        let off = Int32(1 << (scale - 1))
        var q: Int16
        if 0 <= v {
            q = Int16((v + off) >> scale)
        } else {
            q = Int16(-1 * ((-1 * v + off) >> scale))
        }
        
        block.data[i] = Int16(bitPattern: UInt16(bitPattern: (q &<< 1) ^ (q >> 15)))
    }
}

// MARK: - Dequantization

public func dequantizeLow(_ block: inout Block2D, size: Int, scale: Int) {
    dequantize(&block, size: size, scale: (scale + quantizeLowOffset))
}

public func dequantizeLowSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    dequantizeSignedMapping(&block, size: size, scale: (scale + quantizeLowOffset))
}

public func dequantizeMid(_ block: inout Block2D, size: Int, scale: Int) {
    dequantize(&block, size: size, scale: (scale + quantizeMidOffset))
}

public func dequantizeMidSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    dequantizeSignedMapping(&block, size: size, scale: (scale + quantizeMidOffset))
}

public func dequantizeHigh(_ block: inout Block2D, size: Int, scale: Int) {
    dequantize(&block, size: size, scale: (scale + quantizeHighOffset))
}

public func dequantizeHighSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    dequantizeSignedMapping(&block, size: size, scale: (scale + quantizeHighOffset))
}

private func dequantize(_ block: inout Block2D, size: Int, scale: Int) {
    #if arch(arm64) || arch(x86_64)
    let total = (size * size)
    switch total {
    case 16:
        dequantizeSIMD4(&block, scale: scale)
    case 64:
        dequantizeSIMD8(&block, scale: scale)
    case 256:
        dequantizeSIMD16(&block, scale: scale)
    case 1024:
        dequantizeSIMD32(&block, scale: scale)
    default:
        dequantizeScalar(&block, size: size, scale: scale)
    }
    #else
    dequantizeScalar(&block, size: size, scale: scale)
    #endif
}

private func dequantizeSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    #if arch(arm64) || arch(x86_64)
    let total = (size * size)
    switch total {
    case 16:
        dequantizeSIMD4SignedMapping(&block, scale: scale)
    case 64:
        dequantizeSIMD8SignedMapping(&block, scale: scale)
    case 256:
        dequantizeSIMD16SignedMapping(&block, scale: scale)
    case 1024:
        dequantizeSIMD32SignedMapping(&block, scale: scale)
    default:
        dequantizeScalarSignedMapping(&block, size: size, scale: scale)
    }
    #else
    dequantizeScalarSignedMapping(&block, size: size, scale: scale)
    #endif
}

// MARK: - Dequantization SIMD

#if arch(arm64) || arch(x86_64)

private func dequantizeSIMD4(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD4<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 4) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD4<Int16>.self)
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD4<Int16>.self)
        }
    }
}

private func dequantizeSIMD4SignedMapping(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD4<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 4) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD4<Int16>.self)
            
            let s = vec &>> 1
            let m = 0 &- (vec & 1)
            vec = s ^ m
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD4<Int16>.self)
        }
    }
}

private func dequantizeSIMD8(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD8<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 8) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD8<Int16>.self)
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD8<Int16>.self)
        }
    }
}

private func dequantizeSIMD8SignedMapping(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD8<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 8) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD8<Int16>.self)
            
            let s = vec &>> 1
            let m = 0 &- (vec & 1)
            vec = s ^ m
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD8<Int16>.self)
        }
    }
}

private func dequantizeSIMD16(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD16<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 16) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD16<Int16>.self)
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD16<Int16>.self)
        }
    }
}

private func dequantizeSIMD16SignedMapping(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD16<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 16) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD16<Int16>.self)
            
            let s = vec &>> 1
            let m = 0 &- (vec & 1)
            vec = s ^ m
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD16<Int16>.self)
        }
    }
}

private func dequantizeSIMD32(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD32<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 32) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD32<Int16>.self)
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD32<Int16>.self)
        }
    }
}

private func dequantizeSIMD32SignedMapping(_ block: inout Block2D, scale: Int) {
    let scaleVec = SIMD32<Int16>(repeating: Int16(scale))

    block.data.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in stride(from: 0, to: buf.count, by: 32) {
            let p = base.advanced(by: i)
            var vec = UnsafeRawPointer(p).load(as: SIMD32<Int16>.self)
            
            let s = vec &>> 1
            let m = 0 &- (vec & 1)
            vec = s ^ m
            
            vec = vec &<< scaleVec
            UnsafeMutableRawPointer(p).storeBytes(of: vec, as: SIMD32<Int16>.self)
        }
    }
}

#endif  // arch(arm64) || arch(x86_64)

// MARK: - Dequantization Scalar (fallback)

private func dequantizeScalar(_ block: inout Block2D, size: Int, scale: Int) {
    let total = (size * size)
    for i in 0..<total {
        block.data[i] = (block.data[i] &<< scale)
    }
}

private func dequantizeScalarSignedMapping(_ block: inout Block2D, size: Int, scale: Int) {
    let total = (size * size)
    for i in 0..<total {
        var v = block.data[i]
        let u = UInt16(bitPattern: v)
        let s = Int16(bitPattern: (u >> 1))
        let m = (-1 * Int16(bitPattern: (u & 1)))
        v = (s ^ m)
        block.data[i] = (v &<< scale)
    }
}
