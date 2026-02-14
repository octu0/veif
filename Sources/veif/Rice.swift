import Foundation

// MARK: - Helper

public func toUint16(_ n: Int16) -> UInt16 {
    return UInt16(bitPattern: ((n &<< 1) ^ (n >> 15)))
}

public func toInt16(_ u: UInt16) -> Int16 {
    let s = Int16(bitPattern: (u >> 1))
    let m = (-1 * Int16(bitPattern: (u & 1)))
    return (s ^ m)
}

// MARK: - BitWriter

public class BitWriter {
    private var data: Data
    private var cache: UInt8
    private var bits: UInt8
    
    public init(data: inout Data) {
        self.data = data
        self.cache = 0
        self.bits = 0
    }
    
    public func writeBit(_ bit: UInt8) {
        if 0 < bit {
            cache |= (1 << (7 - bits))
        }
        bits += 1
        if bits == 8 {
            data.append(cache)
            bits = 0
            cache = 0
        }
    }
    
    public func writeBits(val: UInt16, n: UInt8) {
        for i in 0..<n {
            let bit = ((val >> (n - 1 - i)) & 1)
            writeBit(UInt8(bit))
        }
    }
    
    public func flush() {
        if 0 < bits {
            data.append(cache)
            bits = 0
            cache = 0
        }
    }
}

// MARK: - RiceWriter

public class RiceWriter {
    private let bw: BitWriter
    private let maxVal: UInt16
    private var zeroCount: UInt16
    private var lastK: UInt8
    
    public init(bw: BitWriter) {
        self.bw = bw
        self.maxVal = 64
        self.zeroCount = 0
        self.lastK = 0
    }
    
    private func writePrimitive(val: UInt16, k: UInt8) {
        let m = (UInt16(1) << k)
        let q = (val / m)
        let r = (val % m)
        
        for _ in 0..<q {
            bw.writeBit(1)
        }
        bw.writeBit(0)
        
        bw.writeBits(val: r, n: k)
    }
    
    public func write(val: UInt16, k: UInt8) {
        lastK = k
        
        if val == 0 {
            if zeroCount == maxVal {
                flushZeros(k: k)
            }
            zeroCount += 1
            return
        }
        
        if 0 < zeroCount {
             flushZeros(k: k)
        }
        
        writePrimitive(val: val, k: k)
    }
    
    private func flushZeros(k: UInt8) {
        if zeroCount == 0 {
            return
        }
        writePrimitive(val: 0, k: k)
        writePrimitive(val: zeroCount, k: k)
        
        zeroCount = 0
    }
    
    public func flush() {
        if 0 < zeroCount {
            flushZeros(k: lastK)
        }
        bw.flush()
    }
}

// MARK: - BitReader

public class BitReader {
    private let data: Data
    private var offset: Int
    private var cache: UInt8
    private var bits: UInt8
    
    public init(data: Data) {
        self.data = data
        self.offset = 0
        self.cache = 0
        self.bits = 0
    }
    
    public func readBit() throws -> UInt8 {
        if bits == 0 {
            if data.count <= offset {
                throw NSError(domain: "BitReaderErr", code: 1, userInfo: [NSLocalizedDescriptionKey: "EOF"])
            }
            cache = data[offset]
            offset += 1
            bits = 8
        }
        bits -= 1
        let bit = ((cache >> bits) & 1)
        return bit
    }
    
    public func readBits(n: UInt8) throws -> UInt16 {
        var val: UInt16 = 0
        for _ in 0..<n {
            let bit = try readBit()
            val = ((val << 1) | UInt16(bit))
        }
        return val
    }
}

// MARK: - RiceReader

public class RiceReader {
    private let br: BitReader
    private var pendingZeros: Int
    
    public init(br: BitReader) {
        self.br = br
        self.pendingZeros = 0
    }
    
    private func readPrimitive(k: UInt8) throws -> UInt16 {
        var q: UInt16 = 0
        while true {
            let bit = try br.readBit()
            if bit == 0 {
                break
            }
            q += 1
        }
        
        let rem64 = try br.readBits(n: k)
        let val = ((q << k) | rem64)
        return val
    }
    
    public func read(k: UInt8) throws -> UInt16 {
        if 0 < pendingZeros {
            pendingZeros -= 1
            return 0
        }
        
        let val = try readPrimitive(k: k)
        
        if val == 0 {
            let count = try readPrimitive(k: k)
            pendingZeros = (Int(count) - 1)
            return 0
        }
        
        return val
    }
}

