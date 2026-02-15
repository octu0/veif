import Foundation

// MARK: - Quantization

struct Quantizer: Sendable {
    public let step: Int16
    public let mul: Int32
    public let shift: Int16 = 16
    
    public init(step: Int) {
        self.step = Int16(step)
        self.mul = Int32((1 << 16) / step)
    }
}

struct QuantizationTable: Sendable {
    public let step: Int16
    public let qLow: Quantizer
    public let qMid: Quantizer
    public let qHigh: Quantizer
    
    public init(baseStep: Int) {
        let s = max(1, baseStep)
        self.step = Int16(s)
        self.qLow  = Quantizer(step: s)
        self.qMid  = Quantizer(step: s * 2)
        self.qHigh = Quantizer(step: s * 4)
    }
}


@inline(__always)
func quantizeLow(_ block: inout Block2D, qt: QuantizationTable) {
    quantize(&block, q: qt.qLow)
}

@inline(__always)
func quantizeLowSignedMapping(_ block: inout Block2D, qt: QuantizationTable) {
    quantizeSignedMapping(&block, q: qt.qLow)
}

@inline(__always)
func quantizeMid(_ block: inout Block2D, qt: QuantizationTable) {
    quantize(&block, q: qt.qMid)
}

@inline(__always)
func quantizeMidSignedMapping(_ block: inout Block2D, qt: QuantizationTable) {
    quantizeSignedMapping(&block, q: qt.qMid)
}

@inline(__always)
func quantizeHigh(_ block: inout Block2D, qt: QuantizationTable) {
    quantize(&block, q: qt.qHigh)
}

@inline(__always)
func quantizeHighSignedMapping(_ block: inout Block2D, qt: QuantizationTable) {
    quantizeSignedMapping(&block, q: qt.qHigh)
}

@inline(__always)
internal func quantize(_ block: inout Block2D, q: Quantizer) {
    #if arch(arm64) || arch(x86_64) || arch(wasm32)
    quantizeSIMD(&block, q: q)
    #else
    quantizeScalar(&block, q: q)
    #endif
}

@inline(__always)
internal func quantizeSignedMapping(_ block: inout Block2D, q: Quantizer) {
    #if arch(arm64) || arch(x86_64) || arch(wasm32)
    quantizeSIMDSignedMapping(&block, q: q)
    #else
    quantizeScalarSignedMapping(&block, q: q)
    #endif
}

// MARK: - Quantization SIMD

#if arch(arm64) || arch(x86_64) || arch(wasm32)

@inline(__always)
private func performQuantizeSIMD8(_ vec: SIMD8<Int16>, mul: Int32, shift: Int32) -> SIMD8<Int16> {
    let zero = SIMD8<Int16>.zero
    let isNeg = vec .< zero
    let absVec = vec.replacing(with: 0 &- vec, where: isNeg)
    
    let low32 = SIMD4<Int32>(
        Int32(absVec[0]), Int32(absVec[1]), Int32(absVec[2]), Int32(absVec[3])
    )
    let high32 = SIMD4<Int32>(
        Int32(absVec[4]), Int32(absVec[5]), Int32(absVec[6]), Int32(absVec[7])
    )
    
    let mulVec = SIMD4<Int32>(repeating: mul)
    let shiftVec = SIMD4<Int32>(repeating: shift)
    
    let resLow32 = (low32 &* mulVec) &>> shiftVec
    let resHigh32 = (high32 &* mulVec) &>> shiftVec
    
    let res = SIMD8<Int16>(
        Int16(resLow32[0]), Int16(resLow32[1]), Int16(resLow32[2]), Int16(resLow32[3]),
        Int16(resHigh32[0]), Int16(resHigh32[1]), Int16(resHigh32[2]), Int16(resHigh32[3])
    )
    
    return res.replacing(with: 0 &- res, where: isNeg)
}

private func quantizeSIMD(_ block: inout Block2D, q: Quantizer) {
    let mul = q.mul
    let shift = Int32(q.shift)
    let count = block.data.count
    
    block.data.withUnsafeMutableBufferPointer { buf in
        var i = 0
        while (i + 8) <= count {
            let ptr = UnsafeBufferPointer(rebasing: buf[i..<(i+8)])
            let vec = SIMD8<Int16>(ptr)
            
            let res = performQuantizeSIMD8(vec, mul: mul, shift: shift)
            
            let rawBase = buf.baseAddress!.advanced(by: i)
            let rawPtr = UnsafeMutableRawPointer(rawBase).assumingMemoryBound(to: SIMD8<Int16>.self)
            rawPtr.pointee = res
            
            i += 8
        }
        while i < count {
            let val = Int32(buf[i])
            let absVal = abs(val)
            let qVal = (absVal &* mul) &>> shift
            buf[i] = Int16(val < 0 ? -qVal : qVal)
            i += 1
        }
    }
}

private func quantizeSIMDSignedMapping(_ block: inout Block2D, q: Quantizer) {
    let mul = q.mul
    let shift = Int32(q.shift)
    let count = block.data.count
    
    block.data.withUnsafeMutableBufferPointer { buf in
        var i = 0
        while (i + 8) <= count {
            let ptr = UnsafeBufferPointer(rebasing: buf[i..<(i+8)])
            let vec = SIMD8<Int16>(ptr)
            
            let res = performQuantizeSIMD8(vec, mul: mul, shift: shift)
            let mask = (res &<< 1) ^ (res &>> 15)
            
            let rawBase = buf.baseAddress!.advanced(by: i)
            let rawPtr = UnsafeMutableRawPointer(rawBase).assumingMemoryBound(to: SIMD8<Int16>.self)
            rawPtr.pointee = mask
            
            i += 8
        }
    }
}

#endif  // arch(arm64) || arch(x86_64)

// MARK: - Quantization Scalar (fallback)

@inline(__always)
internal func quantizeScalar(_ block: inout Block2D, q: Quantizer) {
    let total = block.data.count
    let mul = q.mul
    let shift = Int32(q.shift)
    
    for i in 0..<total {
        let val = Int32(block.data[i])
        let absVal = abs(val)
        let qVal = (absVal &* mul) &>> shift
        block.data[i] = Int16(val < 0 ? -qVal : qVal)
    }
}

@inline(__always)
internal func quantizeScalarSignedMapping(_ block: inout Block2D, q: Quantizer) {
    let total = block.data.count
    let mul = q.mul
    let shift = Int32(q.shift)
    
    for i in 0..<total {
        let val = Int32(block.data[i])
        let absVal = abs(val)
        let qVal = (absVal &* mul) &>> shift
        let v = Int16(val < 0 ? -qVal : qVal)
        block.data[i] = Int16(bitPattern: UInt16(bitPattern: (v &<< 1) ^ (v >> 15)))
    }
}

// MARK: - Dequantization

@inline(__always)
func dequantizeLow(_ block: inout Block2D, qt: QuantizationTable) {
    dequantize(&block, q: qt.qLow)
}

@inline(__always)
func dequantizeLowSignedMapping(_ block: inout Block2D, qt: QuantizationTable) {
    dequantizeSignedMapping(&block, q: qt.qLow)
}

@inline(__always)
func dequantizeMid(_ block: inout Block2D, qt: QuantizationTable) {
    dequantize(&block, q: qt.qMid)
}

@inline(__always)
func dequantizeMidSignedMapping(_ block: inout Block2D, qt: QuantizationTable) {
    dequantizeSignedMapping(&block, q: qt.qMid)
}

@inline(__always)
func dequantizeHigh(_ block: inout Block2D, qt: QuantizationTable) {
    dequantize(&block, q: qt.qHigh)
}

@inline(__always)
func dequantizeHighSignedMapping(_ block: inout Block2D, qt: QuantizationTable) {
    dequantizeSignedMapping(&block, q: qt.qHigh)
}

@inline(__always)
internal func dequantize(_ block: inout Block2D, q: Quantizer) {
    #if arch(arm64) || arch(x86_64) || arch(wasm32)
    dequantizeSIMD(&block, q: q)
    #else
    dequantizeScalar(&block, q: q)
    #endif
}

@inline(__always)
internal func dequantizeSignedMapping(_ block: inout Block2D, q: Quantizer) {
    #if arch(arm64) || arch(x86_64) || arch(wasm32)
    dequantizeSIMDSignedMapping(&block, q: q)
    #else
    dequantizeScalarSignedMapping(&block, q: q)
    #endif
}

// MARK: - Dequantization SIMD

#if arch(arm64) || arch(x86_64) || arch(wasm32)

@inline(__always)
private func performDequantizeSIMD8(_ vec: SIMD8<Int16>, step: Int32) -> SIMD8<Int16> {
    let vLow32 = SIMD4<Int32>(
        Int32(vec[0]), Int32(vec[1]), Int32(vec[2]), Int32(vec[3])
    )
    let vHigh32 = SIMD4<Int32>(
        Int32(vec[4]), Int32(vec[5]), Int32(vec[6]), Int32(vec[7])
    )
    
    let stepVec = SIMD4<Int32>(repeating: step)
    let rLow32 = vLow32 &* stepVec
    let rHigh32 = vHigh32 &* stepVec
    
    return SIMD8<Int16>(
        Int16(clamping: rLow32[0]), Int16(clamping: rLow32[1]), Int16(clamping: rLow32[2]), Int16(clamping: rLow32[3]),
        Int16(clamping: rHigh32[0]), Int16(clamping: rHigh32[1]), Int16(clamping: rHigh32[2]), Int16(clamping: rHigh32[3])
    )
}

private func dequantizeSIMD(_ block: inout Block2D, q: Quantizer) {
    let step = Int32(q.step)
    let count = block.data.count
    
    block.data.withUnsafeMutableBufferPointer { buf in
        var i = 0
        while (i + 8) <= count {
            let ptr = UnsafeBufferPointer(rebasing: buf[i..<(i+8)])
            let vec = SIMD8<Int16>(ptr)
            
            let res = performDequantizeSIMD8(vec, step: step)
            
            let rawBase = buf.baseAddress!.advanced(by: i)
            let rawPtr = UnsafeMutableRawPointer(rawBase).assumingMemoryBound(to: SIMD8<Int16>.self)
            rawPtr.pointee = res
            
            i += 8
        }
        
        while i < count {
            let val = Int32(buf[i])
            let res = val &* step
            buf[i] = Int16(clamping: res)
            i += 1
        }
    }
}

private func dequantizeSIMDSignedMapping(_ block: inout Block2D, q: Quantizer) {
    let step = Int32(q.step)
    let count = block.data.count
    
    block.data.withUnsafeMutableBufferPointer { buf in
        var i = 0
        while (i + 8) <= count {
            let ptr = UnsafeBufferPointer(rebasing: buf[i..<(i+8)])
            let vec = SIMD8<Int16>(ptr)
            
            let mask = 0 &- (vec & 1) // 奇数なら全ビット1 (-1), 偶数なら0
            let logicalShift = (vec &>> 1) & 0x7FFF // 論理右シフト
            let decoded = logicalShift ^ mask
            
            let res = performDequantizeSIMD8(decoded, step: step)
            
            let rawBase = buf.baseAddress!.advanced(by: i)
            let rawPtr = UnsafeMutableRawPointer(rawBase).assumingMemoryBound(to: SIMD8<Int16>.self)
            rawPtr.pointee = res
            
            i += 8
        }
        
        while i < count {
            let val = Int32(buf[i])
            let res = val &* step
            buf[i] = Int16(clamping: res)
            i += 1
        }
    }
}

#endif  // arch(arm64) || arch(x86_64)

// MARK: - Dequantization Scalar (fallback)

@inline(__always)
internal func dequantizeScalar(_ block: inout Block2D, q: Quantizer) {
    let step = Int32(q.step)
    let total = block.data.count
    
    block.data.withUnsafeMutableBufferPointer { ptr in
        for i in 0..<total {
            let val = Int32(ptr[i])
            ptr[i] = Int16(clamping: (val &* step))
        }
    }
}

@inline(__always)
internal func dequantizeScalarSignedMapping(_ block: inout Block2D, q: Quantizer) {
    let step = Int32(q.step)
    let total = block.data.count
    
    block.data.withUnsafeMutableBufferPointer { ptr in
        for i in 0..<total {
            let uVal = UInt16(bitPattern: ptr[i])
            let decodedUInt = (uVal >> 1) ^ (0 &- (uVal & 1))
            let decoded = Int16(bitPattern: decodedUInt)
            ptr[i] = Int16(clamping: Int32(decoded) &* step)
        }
    }
}
