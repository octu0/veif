import Foundation
import Accelerate

// MARK: - DWT Structures

public struct Subbands {
    public var ll: Block2D
    public var hl: Block2D
    public var lh: Block2D
    public var hh: Block2D
    public let size: Int
}

// MARK: - LeGall 5/3 Lifting

@inline(__always)
public func lift53(_ buffer: UnsafeMutableBufferPointer<Int16>, count: Int, stride: Int) {
    #if arch(arm64) || arch(x86_64)
    switch count {
    case 8:
        lift53SIMD4(buffer, stride: stride)
    case 16:
        lift53SIMD8(buffer, stride: stride)
    case 32:
        lift53SIMD16(buffer, stride: stride)
    default:
        lift53Scalar(buffer, count: count, stride: stride)
    }
    #else
    lift53Scalar(buffer, count: count, stride: stride)
    #endif
}

@inline(__always)
public func invLift53(_ buffer: UnsafeMutableBufferPointer<Int16>, count: Int, stride: Int) {
    #if arch(arm64) || arch(x86_64)
    switch count {
    case 8:
        invLift53SIMD4(buffer, stride: stride)
    case 16:
        invLift53SIMD8(buffer, stride: stride)
    case 32:
        invLift53SIMD16(buffer, stride: stride)
    default:
        invLift53Scalar(buffer, count: count, stride: stride)
    }
    #else
    invLift53Scalar(buffer, count: count, stride: stride)
    #endif
}

// MARK: - Lifting Scalar (fallback)

internal func lift53Scalar(_ buffer: UnsafeMutableBufferPointer<Int16>, count: Int, stride: Int) {
    let half = (count / 2)
    var low = [Int16](repeating: 0, count: half)
    var high = [Int16](repeating: 0, count: half)
    
    // Split
    for i in 0..<half {
        low[i] = buffer[2 * i * stride]
        high[i] = buffer[(2 * i + 1) * stride]
    }
    
    // Predict
    for i in 0..<half {
        let l = Int32(low[i])
        var r = Int32(low[i])
        if (i + 1) < half {
            r = Int32(low[i + 1])
        }
        high[i] -= Int16((l + r) >> 1)
    }
    
    // Update
    for i in 0..<half {
        let d = Int32(high[i])
        var dp = Int32(high[i])
        if 0 <= (i - 1) {
            dp = Int32(high[i - 1])
        }
        low[i] += Int16(((dp + d) + 2) >> 2)
    }
    
    // Merge
    for i in 0..<half {
        buffer[i * stride] = low[i]
        buffer[(half + i) * stride] = high[i]
    }
}

internal func invLift53Scalar(_ buffer: UnsafeMutableBufferPointer<Int16>, count: Int, stride: Int) {
    let half = (count / 2)
    var low = [Int16](repeating: 0, count: half)
    var high = [Int16](repeating: 0, count: half)
    
    // Split
    for i in 0..<half {
        low[i] = buffer[i * stride]
        high[i] = buffer[(half + i) * stride]
    }
    
    // Inv Update
    for i in 0..<half {
        let d = Int32(high[i])
        var dp = Int32(high[i])
        if 0 <= (i - 1) {
            dp = Int32(high[i - 1])
        }
        low[i] -= Int16(((dp + d) + 2) >> 2)
    }
    
    // Inv Predict
    for i in 0..<half {
        let l = Int32(low[i])
        var r = Int32(low[i])
        if (i + 1) < half {
            r = Int32(low[i + 1])
        }
        high[i] += Int16((l + r) >> 1)
    }
    
    // Merge
    for i in 0..<half {
        buffer[2 * i * stride] = low[i]
        buffer[(2 * i + 1) * stride] = high[i]
    }
}

// MARK: - Lifting SIMD

@inlinable @inline(__always)
func lift53SIMD4(_ buffer: UnsafeMutableBufferPointer<Int16>, stride: Int) {
    // size = 8, half = 4
    
    // Split
    // low: 0, 2, 4, 6
    // high: 1, 3, 5, 7
    // Access with stride: buffer[i * stride]
    var low = SIMD4<Int16>(buffer[0 * stride], buffer[2 * stride], buffer[4 * stride], buffer[6 * stride])
    var high = SIMD4<Int16>(buffer[1 * stride], buffer[3 * stride], buffer[5 * stride], buffer[7 * stride])
    
    // Predict
    let lowShifted = SIMD4<Int16>(low[1], low[2], low[3], low[3])
    high &-= (low &+ lowShifted) &>> 1
    
    // Update
    let highShifted = SIMD4<Int16>(high[0], high[0], high[1], high[2])
    low &+= (highShifted &+ high &+ 2) &>> 2
    
    // Merge
    buffer[0 * stride] = low[0]; buffer[1 * stride] = low[1]; buffer[2 * stride] = low[2]; buffer[3 * stride] = low[3]
    buffer[4 * stride] = high[0]; buffer[5 * stride] = high[1]; buffer[6 * stride] = high[2]; buffer[7 * stride] = high[3]
}

@inlinable @inline(__always)
func lift53SIMD8(_ buffer: UnsafeMutableBufferPointer<Int16>, stride: Int) {
    // size = 16, half = 8
    
    // Split
    var low = SIMD8<Int16>(
        buffer[0 * stride], buffer[2 * stride], buffer[4 * stride], buffer[6 * stride],
        buffer[8 * stride], buffer[10 * stride], buffer[12 * stride], buffer[14 * stride]
    )
    var high = SIMD8<Int16>(
        buffer[1 * stride], buffer[3 * stride], buffer[5 * stride], buffer[7 * stride],
        buffer[9 * stride], buffer[11 * stride], buffer[13 * stride], buffer[15 * stride]
    )
    
    // Predict
    let lowShifted = SIMD8<Int16>(low[1], low[2], low[3], low[4], low[5], low[6], low[7], low[7])
    high &-= (low &+ lowShifted) &>> 1
    
    // Update
    let highShifted = SIMD8<Int16>(high[0], high[0], high[1], high[2], high[3], high[4], high[5], high[6])
    low &+= (highShifted &+ high &+ 2) &>> 2
    
    // Merge
    buffer[0 * stride] = low[0]; buffer[1 * stride] = low[1]; buffer[2 * stride] = low[2]; buffer[3 * stride] = low[3]
    buffer[4 * stride] = low[4]; buffer[5 * stride] = low[5]; buffer[6 * stride] = low[6]; buffer[7 * stride] = low[7]
    
    buffer[8 * stride] = high[0]; buffer[9 * stride] = high[1]; buffer[10 * stride] = high[2]; buffer[11 * stride] = high[3]
    buffer[12 * stride] = high[4]; buffer[13 * stride] = high[5]; buffer[14 * stride] = high[6]; buffer[15 * stride] = high[7]
}

@inlinable @inline(__always)
func lift53SIMD16(_ buffer: UnsafeMutableBufferPointer<Int16>, stride: Int) {
    // size = 32, half = 16
    
    // Split
    var low = SIMD16<Int16>(
        buffer[0 * stride], buffer[2 * stride], buffer[4 * stride], buffer[6 * stride],
        buffer[8 * stride], buffer[10 * stride], buffer[12 * stride], buffer[14 * stride],
        buffer[16 * stride], buffer[18 * stride], buffer[20 * stride], buffer[22 * stride],
        buffer[24 * stride], buffer[26 * stride], buffer[28 * stride], buffer[30 * stride]
    )
    var high = SIMD16<Int16>(
        buffer[1 * stride], buffer[3 * stride], buffer[5 * stride], buffer[7 * stride],
        buffer[9 * stride], buffer[11 * stride], buffer[13 * stride], buffer[15 * stride],
        buffer[17 * stride], buffer[19 * stride], buffer[21 * stride], buffer[23 * stride],
        buffer[25 * stride], buffer[27 * stride], buffer[29 * stride], buffer[31 * stride]
    )
    
    // Predict
    let lowShifted = SIMD16<Int16>(
        low[1], low[2], low[3], low[4], low[5], low[6], low[7], low[8],
        low[9], low[10], low[11], low[12], low[13], low[14], low[15], low[15]
    )
    high &-= (low &+ lowShifted) &>> 1
    
    // Update
    let highShifted = SIMD16<Int16>(
        high[0], high[0], high[1], high[2], high[3], high[4], high[5], high[6],
        high[7], high[8], high[9], high[10], high[11], high[12], high[13], high[14]
    )
    low &+= (highShifted &+ high &+ 2) &>> 2
    
    // Merge
    for i in 0..<16 {
        buffer[(0 + i) * stride] = low[i]
        buffer[(16 + i) * stride] = high[i]
    }
}

@inlinable @inline(__always)
func invLift53SIMD4(_ buffer: UnsafeMutableBufferPointer<Int16>, stride: Int) {
    // size = 8, half = 4
    
    // Split
    // low: data[0...3]
    // high: data[4...7]
    var low = SIMD4<Int16>(buffer[0 * stride], buffer[1 * stride], buffer[2 * stride], buffer[3 * stride])
    var high = SIMD4<Int16>(buffer[4 * stride], buffer[5 * stride], buffer[6 * stride], buffer[7 * stride])
    
    // Inv Update
    let highShifted = SIMD4<Int16>(high[0], high[0], high[1], high[2])
    low &-= (highShifted &+ high &+ 2) &>> 2
    
    // Inv Predict
    let lowShifted = SIMD4<Int16>(low[1], low[2], low[3], low[3])
    high &+= (low &+ lowShifted) &>> 1
    
    // Merge (Interleave)
    // data[2*i] = low[i], data[2*i+1] = high[i]
    buffer[0 * stride] = low[0]; buffer[1 * stride] = high[0]
    buffer[2 * stride] = low[1]; buffer[3 * stride] = high[1]
    buffer[4 * stride] = low[2]; buffer[5 * stride] = high[2]
    buffer[6 * stride] = low[3]; buffer[7 * stride] = high[3]
}

@inlinable @inline(__always)
func invLift53SIMD8(_ buffer: UnsafeMutableBufferPointer<Int16>, stride: Int) {
    // size = 16, half = 8
    
    // Split
    var low = SIMD8<Int16>(
        buffer[0 * stride], buffer[1 * stride], buffer[2 * stride], buffer[3 * stride],
        buffer[4 * stride], buffer[5 * stride], buffer[6 * stride], buffer[7 * stride]
    )
    var high = SIMD8<Int16>(
        buffer[8 * stride], buffer[9 * stride], buffer[10 * stride], buffer[11 * stride],
        buffer[12 * stride], buffer[13 * stride], buffer[14 * stride], buffer[15 * stride]
    )
    
    // Inv Update
    let highShifted = SIMD8<Int16>(high[0], high[0], high[1], high[2], high[3], high[4], high[5], high[6])
    low &-= (highShifted &+ high &+ 2) &>> 2
    
    // Inv Predict
    let lowShifted = SIMD8<Int16>(low[1], low[2], low[3], low[4], low[5], low[6], low[7], low[7])
    high &+= (low &+ lowShifted) &>> 1
    
    // Merge
    buffer[0 * stride] = low[0]; buffer[1 * stride] = high[0]
    buffer[2 * stride] = low[1]; buffer[3 * stride] = high[1]
    buffer[4 * stride] = low[2]; buffer[5 * stride] = high[2]
    buffer[6 * stride] = low[3]; buffer[7 * stride] = high[3]
    
    buffer[8 * stride] = low[4]; buffer[9 * stride] = high[4]
    buffer[10 * stride] = low[5]; buffer[11 * stride] = high[5]
    buffer[12 * stride] = low[6]; buffer[13 * stride] = high[6]
    buffer[14 * stride] = low[7]; buffer[15 * stride] = high[7]
}

@inlinable @inline(__always)
func invLift53SIMD16(_ buffer: UnsafeMutableBufferPointer<Int16>, stride: Int) {
    // size = 32, half = 16
    
    // Split
    var low = SIMD16<Int16>(
        buffer[0 * stride], buffer[1 * stride], buffer[2 * stride], buffer[3 * stride],
        buffer[4 * stride], buffer[5 * stride], buffer[6 * stride], buffer[7 * stride],
        buffer[8 * stride], buffer[9 * stride], buffer[10 * stride], buffer[11 * stride],
        buffer[12 * stride], buffer[13 * stride], buffer[14 * stride], buffer[15 * stride]
    )
    var high = SIMD16<Int16>(
        buffer[16 * stride], buffer[17 * stride], buffer[18 * stride], buffer[19 * stride],
        buffer[20 * stride], buffer[21 * stride], buffer[22 * stride], buffer[23 * stride],
        buffer[24 * stride], buffer[25 * stride], buffer[26 * stride], buffer[27 * stride],
        buffer[28 * stride], buffer[29 * stride], buffer[30 * stride], buffer[31 * stride]
    )
    
    // Inv Update
    let highShifted = SIMD16<Int16>(
        high[0], high[0], high[1], high[2], high[3], high[4], high[5], high[6],
        high[7], high[8], high[9], high[10], high[11], high[12], high[13], high[14]
    )
    low &-= (highShifted &+ high &+ 2) &>> 2
    
    // Inv Predict
    let lowShifted = SIMD16<Int16>(
        low[1], low[2], low[3], low[4], low[5], low[6], low[7], low[8],
        low[9], low[10], low[11], low[12], low[13], low[14], low[15], low[15]
    )
    high &+= (low &+ lowShifted) &>> 1
    
    // Merge
    for i in 0..<16 {
        buffer[2 * i * stride] = low[i]
        buffer[(2 * i + 1) * stride] = high[i]
    }
}

// MARK: - Specialized 2D DWT

func dwt2dSIMD4(_ block: inout Block2D) -> Subbands {
    let size = 8
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        for y in 0..<size {
            let rowBuffer = UnsafeMutableBufferPointer(start: base + (y * width), count: size)
            lift53SIMD4(rowBuffer, stride: 1)
        }
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            lift53SIMD4(colBuffer, stride: width)
        }
    }
    return splitSubbands(&block, size: size)
}

func dwt2dSIMD8(_ block: inout Block2D) -> Subbands {
    let size = 16
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        for y in 0..<size {
            let rowBuffer = UnsafeMutableBufferPointer(start: base + (y * width), count: size)
            lift53SIMD8(rowBuffer, stride: 1)
        }
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            lift53SIMD8(colBuffer, stride: width)
        }
    }
    return splitSubbands(&block, size: size)
}

func dwt2dSIMD16(_ block: inout Block2D) -> Subbands {
    let size = 32
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        for y in 0..<size {
            let rowBuffer = UnsafeMutableBufferPointer(start: base + (y * width), count: size)
            lift53SIMD16(rowBuffer, stride: 1)
        }
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            lift53SIMD16(colBuffer, stride: width)
        }
    }
    return splitSubbands(&block, size: size)
}

func invDwt2dSIMD4(_ sub: Subbands) -> Block2D {
    let size = 8
    let block = mergeSubbands(sub, size: size)
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            invLift53SIMD4(colBuffer, stride: width)
        }
        for y in 0..<size {
            let rowBuffer = UnsafeMutableBufferPointer(start: base + (y * width), count: size)
            invLift53SIMD4(rowBuffer, stride: 1)
        }
    }
    return block
}

func invDwt2dSIMD8(_ sub: Subbands) -> Block2D {
    let size = 16
    let block = mergeSubbands(sub, size: size)
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            invLift53SIMD8(colBuffer, stride: width)
        }
        for y in 0..<size {
            let rowBuffer = UnsafeMutableBufferPointer(start: base + (y * width), count: size)
            invLift53SIMD8(rowBuffer, stride: 1)
        }
    }
    return block
}

func invDwt2dSIMD16(_ sub: Subbands) -> Block2D {
    let size = 32
    let block = mergeSubbands(sub, size: size)
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            invLift53SIMD16(colBuffer, stride: width)
        }
        for y in 0..<size {
            let rowBuffer = UnsafeMutableBufferPointer(start: base + (y * width), count: size)
            invLift53SIMD16(rowBuffer, stride: 1)
        }
    }
    return block
}

private func splitSubbands(_ block: inout Block2D, size: Int) -> Subbands {
    let half = size / 2
    let sub = Subbands(
        ll: Block2D(width: half, height: half),
        hl: Block2D(width: half, height: half),
        lh: Block2D(width: half, height: half),
        hh: Block2D(width: half, height: half),
        size: half
    )
    
    block.data.withUnsafeBufferPointer { blockPtr in
        guard let bBase = blockPtr.baseAddress else { return }
        
        sub.ll.data.withUnsafeMutableBufferPointer { llPtr in
            sub.hl.data.withUnsafeMutableBufferPointer { hlPtr in
                sub.lh.data.withUnsafeMutableBufferPointer { lhPtr in
                    sub.hh.data.withUnsafeMutableBufferPointer { hhPtr in
                        guard let llBase = llPtr.baseAddress,
                              let hlBase = hlPtr.baseAddress,
                              let lhBase = lhPtr.baseAddress,
                              let hhBase = hhPtr.baseAddress else { return }
                        
                        let bWidth = block.width
                        let sWidth = half
                        
                        for y in 0..<half {
                            let bRowOff = (y * bWidth)
                            let sRowOff = (y * sWidth)
                            
                            // Top half (LL and HL)
                            for x in 0..<half {
                                llBase[sRowOff + x] = bBase[bRowOff + x]
                                hlBase[sRowOff + x] = bBase[bRowOff + x + half]
                            }
                            
                            // Bottom half (LH and HH)
                            let bLowRowOff = ((y + half) * bWidth)
                            for x in 0..<half {
                                lhBase[sRowOff + x] = bBase[bLowRowOff + x]
                                hhBase[sRowOff + x] = bBase[bLowRowOff + x + half]
                            }
                        }
                    }
                }
            }
        }
    }
    return sub
}

private func mergeSubbands(_ sub: Subbands, size: Int) -> Block2D {
    let half = sub.size
    let block = Block2D(width: size, height: size)
    
    block.data.withUnsafeMutableBufferPointer { blockPtr in
        guard let bBase = blockPtr.baseAddress else { return }
        
        sub.ll.data.withUnsafeBufferPointer { llPtr in
            sub.hl.data.withUnsafeBufferPointer { hlPtr in
                sub.lh.data.withUnsafeBufferPointer { lhPtr in
                    sub.hh.data.withUnsafeBufferPointer { hhPtr in
                        guard let llBase = llPtr.baseAddress,
                              let hlBase = hlPtr.baseAddress,
                              let lhBase = lhPtr.baseAddress,
                              let hhBase = hhPtr.baseAddress else { return }
                        
                        let bWidth = block.width
                        let sWidth = half
                        
                        for y in 0..<half {
                            let bRowOff = (y * bWidth)
                            let sRowOff = (y * sWidth)
                            
                            // Top half (LL and HL)
                            for x in 0..<half {
                                bBase[bRowOff + x] = llBase[sRowOff + x]
                                bBase[bRowOff + x + half] = hlBase[sRowOff + x]
                            }
                            
                            // Bottom half (LH and HH)
                            let bLowRowOff = ((y + half) * bWidth)
                            for x in 0..<half {
                                bBase[bLowRowOff + x] = lhBase[sRowOff + x]
                                bBase[bLowRowOff + x + half] = hhBase[sRowOff + x]
                            }
                        }
                    }
                }
            }
        }
    }
    return block
}

// MARK: - 2D DWT

@inline(__always)
public func dwt2d(_ block: inout Block2D, size: Int) -> Subbands {
    #if arch(arm64) || arch(x86_64)
    switch size {
    case 8:
        return dwt2dSIMD4(&block)
    case 16:
        return dwt2dSIMD8(&block)
    case 32:
        return dwt2dSIMD16(&block)
    default:
        return dwt2dScalar(&block, size: size)
    }
    #else
    return dwt2dScalar(&block, size: size)
    #endif
}

internal func dwt2dScalar(_ block: inout Block2D, size: Int) -> Subbands {
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        
        // Horizontal (stride = 1)
        for y in 0..<size {
            let offset = (y * block.width)
            let rowBuffer = UnsafeMutableBufferPointer(start: base + offset, count: size)
            lift53(rowBuffer, count: size, stride: 1)
        }
        
        // Vertical (stride = width)
        let width = block.width
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            lift53(colBuffer, count: size, stride: width)
        }
    }
    
    return splitSubbands(&block, size: size)
}

@inline(__always)
public func invDwt2d(_ sub: Subbands) -> Block2D {
    let size = (sub.size * 2)
    #if arch(arm64) || arch(x86_64)
    switch size {
    case 8:
        return invDwt2dSIMD4(sub)
    case 16:
        return invDwt2dSIMD8(sub)
    case 32:
        return invDwt2dSIMD16(sub)
    default:
        return invDwt2dScalar(sub)
    }
    #else
    return invDwt2dScalar(sub)
    #endif
}

internal func invDwt2dScalar(_ sub: Subbands) -> Block2D {
    let size = (sub.size * 2)
    let block = mergeSubbands(sub, size: size)
    
    block.data.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        let width = block.width
        
        // Vertical (stride = width)
        let colCount = ((size - 1) * width) + 1
        for x in 0..<size {
            let colBuffer = UnsafeMutableBufferPointer(start: base + x, count: colCount)
            invLift53(colBuffer, count: size, stride: width)
        }
        
        // Horizontal (stride = 1)
        for y in 0..<size {
            let offset = (y * width)
            let rowBuffer = UnsafeMutableBufferPointer(start: base + offset, count: size)
            invLift53(rowBuffer, count: size, stride: 1)
        }
    }
    
    return block
}
