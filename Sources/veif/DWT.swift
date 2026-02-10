import Foundation

func lift53(arr: UnsafeMutablePointer<Int16>, n: Int) {
    let half = n / 2
    var low = [Int16](repeating: 0, count: half)
    var high = [Int16](repeating: 0, count: half)

    // Split even/odd
    for i in 0..<half {
        low[i] = arr[2 * i]
        high[i] = arr[(2 * i) + 1]
    }

    // Predict
    for i in 0..<half {
        let l = Int32(low[i])
        var r = Int32(low[i])
        if i + 1 < half {
            r = Int32(low[i + 1])
        }
        high[i] -= Int16((l + r) >> 1)
    }

    // Update
    for i in 0..<half {
        let d = Int32(high[i])
        var dp = Int32(high[i])
        if 0 <= i - 1 {
            dp = Int32(high[i - 1])
        }
        low[i] += Int16((dp + d + 2) >> 2)
    }

    // Merge back
    for i in 0..<half {
        arr[i] = low[i]
        arr[half + i] = high[i]
    }
}

func invLift53(arr: UnsafeMutablePointer<Int16>, n: Int) {
    let half = n / 2
    var low = [Int16](repeating: 0, count: half)
    var high = [Int16](repeating: 0, count: half)

    // Split
    for i in 0..<half {
        low[i] = arr[i]
        high[i] = arr[half + i]
    }

    // Inv Update
    for i in 0..<half {
        let d = Int32(high[i])
        var dp = Int32(high[i])
        if 0 <= i - 1 {
            dp = Int32(high[i - 1])
        }
        low[i] -= Int16((dp + d + 2) >> 2)
    }

    // Inv Predict
    for i in 0..<half {
        let l = Int32(low[i])
        var r = Int32(low[i])
        if i + 1 < half {
            r = Int32(low[i + 1])
        }
        high[i] += Int16((l + r) >> 1)
    }

    // Merge back interleaved
    for i in 0..<half {
        arr[2 * i] = low[i]
        arr[(2 * i) + 1] = high[i]
    }
}

func dwtBlock(data: UnsafeMutablePointer<Int16>, size: Int) {
    var buf = [Int16](repeating: 0, count: size)

    // Row transform
    for y in 0..<size {
        // data[y*size] is start of row
        lift53(arr: data.advanced(by: y * size), n: size)
    }

    // Col transform
    for x in 0..<size {
        // Gather column
        for y in 0..<size {
            buf[y] = data[y * size + x]
        }

        // Lift
        buf.withUnsafeMutableBufferPointer { bp in
            lift53(arr: bp.baseAddress!, n: size)
        }

        // Scatter column
        for y in 0..<size {
            data[y * size + x] = buf[y]
        }
    }
}

func invDwtBlock(data: UnsafeMutablePointer<Int16>, size: Int) {
    var buf = [Int16](repeating: 0, count: size)

    // Inv Col transform
    for x in 0..<size {
        for y in 0..<size {
            buf[y] = data[y * size + x]
        }
        buf.withUnsafeMutableBufferPointer { bp in
            invLift53(arr: bp.baseAddress!, n: size)
        }
        for y in 0..<size {
            data[y * size + x] = buf[y]
        }
    }

    // Inv Row transform
    for y in 0..<size {
        invLift53(arr: data.advanced(by: y * size), n: size)
    }
}

func dwtBlock2Level(data: UnsafeMutablePointer<Int16>, size: Int) {
    dwtBlock(data: data, size: size)

    if size < 16 {
        return
    }

    let half = size / 2

    var ll = [Int16](repeating: 0, count: half * half)
    for y in 0..<half {
        for x in 0..<half {
            ll[y * half + x] = data[y * size + x]
        }
    }

    ll.withUnsafeMutableBufferPointer { bp in
        dwtBlock(data: bp.baseAddress!, size: half)
    }

    for y in 0..<half {
        for x in 0..<half {
            data[y * size + x] = ll[y * half + x]
        }
    }
}

func invDwtBlock2Level(data: UnsafeMutablePointer<Int16>, size: Int) {
    if 16 <= size {
        let half = size / 2
        var ll = [Int16](repeating: 0, count: half * half)
        for y in 0..<half {
            for x in 0..<half {
                ll[y * half + x] = data[y * size + x]
            }
        }

        ll.withUnsafeMutableBufferPointer { bp in
            invDwtBlock(data: bp.baseAddress!, size: half)
        }

        for y in 0..<half {
            for x in 0..<half {
                data[y * size + x] = ll[y * half + x]
            }
        }
    }
    invDwtBlock(data: data, size: size)
}

func dwtPlane(data: inout [Int16], width: Int, height: Int) {
    // Row transform
    data.withUnsafeMutableBufferPointer { bp in
        let ptr = bp.baseAddress!
        for y in 0..<height {
            lift53(arr: ptr.advanced(by: y * width), n: width)
        }
    }

    // Col transform
    var col = [Int16](repeating: 0, count: height)
    for x in 0..<width {
        for y in 0..<height {
            col[y] = data[y * width + x]
        }

        col.withUnsafeMutableBufferPointer { bp in
            lift53(arr: bp.baseAddress!, n: height)
        }

        for y in 0..<height {
            data[y * width + x] = col[y]
        }
    }
}

func invDwtPlane(data: inout [Int16], width: Int, height: Int) {
    // Inv Col transform
    var col = [Int16](repeating: 0, count: height)
    for x in 0..<width {
        for y in 0..<height {
            col[y] = data[y * width + x]
        }

        col.withUnsafeMutableBufferPointer { bp in
            invLift53(arr: bp.baseAddress!, n: height)
        }

        for y in 0..<height {
            data[y * width + x] = col[y]
        }
    }

    // Inv Row transform
    data.withUnsafeMutableBufferPointer { bp in
        let ptr = bp.baseAddress!
        for y in 0..<height {
            invLift53(arr: ptr.advanced(by: y * width), n: width)
        }
    }
}
