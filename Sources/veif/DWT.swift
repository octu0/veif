
// MARK: - DWT Structures

public struct Subbands {
    public var ll: [[Int16]]
    public var hl: [[Int16]]
    public var lh: [[Int16]]
    public var hh: [[Int16]]
    public let size: Int
}

// MARK: - LeGall 5/3 Lifting

public func lift53(_ data: inout [Int16]) {
    let n = data.count
    let half = (n / 2)
    var low = [Int16](repeating: 0, count: half)
    var high = [Int16](repeating: 0, count: half)
    
    // Split
    for i in 0..<half {
        low[i] = data[2 * i]
        high[i] = data[(2 * i) + 1]
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
        data[i] = low[i]
        data[half + i] = high[i]
    }
}

public func invLift53(_ data: inout [Int16]) {
    let n = data.count
    let half = (n / 2)
    var low = [Int16](repeating: 0, count: half)
    var high = [Int16](repeating: 0, count: half)
    
    // Split
    for i in 0..<half {
        low[i] = data[i]
        high[i] = data[half + i]
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
        data[2 * i] = low[i]
        data[(2 * i) + 1] = high[i]
    }
}

// MARK: - 2D DWT

public func dwt2d(_ data: inout [[Int16]], size: Int) -> Subbands {
    // Horizontal
    for y in 0..<size {
        lift53(&data[y])
    }
    
    // Vertical
    var col = [Int16](repeating: 0, count: size)
    for x in 0..<size {
        for y in 0..<size {
            col[y] = data[y][x]
        }
        lift53(&col)
        for y in 0..<size {
            data[y][x] = col[y]
        }
    }
    
    let half = ((size + 1) / 2)
    
    var sub = Subbands(
        ll: [[Int16]](repeating: [Int16](repeating: 0, count: half), count: half),
        hl: [[Int16]](repeating: [Int16](repeating: 0, count: half), count: half),
        lh: [[Int16]](repeating: [Int16](repeating: 0, count: half), count: half),
        hh: [[Int16]](repeating: [Int16](repeating: 0, count: half), count: half),
        size: half
    )
    
    for y in 0..<half {
        for x in 0..<size {
            let val = data[y][x]
            if x < half {
                sub.ll[y][x] = val // Top-Left
            } else {
                sub.hl[y][x - half] = val // Top-Right
            }
        }
    }
    
    for y in half..<size {
        for x in 0..<size {
            let val = data[y][x]
            if x < half {
                sub.lh[y - half][x] = val // Bottom-Left
            } else {
                sub.hh[y - half][x - half] = val // Bottom-Right
            }
        }
    }
    
    return sub
}

public func invDwt2d(_ sub: Subbands) -> [[Int16]] {
    let half = sub.size
    let size = (sub.size * 2)
    
    var data = [[Int16]](repeating: [Int16](repeating: 0, count: size), count: size)
    
    for y in 0..<half {
        for x in 0..<size {
            if x < half {
                data[y][x] = sub.ll[y][x]
            } else {
                data[y][x] = sub.hl[y][x - half]
            }
        }
    }
    
    for y in half..<size {
        for x in 0..<size {
            if x < half {
                data[y][x] = sub.lh[y - half][x]
            } else {
                data[y][x] = sub.hh[y - half][x - half]
            }
        }
    }
    
    // Vertical
    var col = [Int16](repeating: 0, count: size)
    for x in 0..<size {
        for y in 0..<size {
            col[y] = data[y][x]
        }
        invLift53(&col)
        for y in 0..<size {
            data[y][x] = col[y]
        }
    }
    
    // Horizontal
    for y in 0..<size {
        invLift53(&data[y])
    }
    
    return data
}
