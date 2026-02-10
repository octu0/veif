import Foundation

enum BitError: Error {
    case eoF
}

class BitWriter {
    private(set) var data: Data
    private var cache: UInt8
    private var bits: UInt8

    init() {
        self.data = Data()
        self.cache = 0
        self.bits = 0
    }

    func writeBit(_ bit: UInt8) {
        if 0 < bit {
            self.cache |= (1 << (7 - self.bits))
        }
        self.bits += 1
        if self.bits == 8 {
            self.data.append(self.cache)
            self.bits = 0
            self.cache = 0
        }
    }

    func writeBits(val: UInt16, n: UInt8) {
        for i in 0..<n {
            let shift = (n - 1) - i
            let bit = (val >> shift) & 1
            writeBit(UInt8(bit))
        }
    }

    func flush() {
        if 0 < self.bits {
            self.data.append(self.cache)
            self.bits = 0
            self.cache = 0
        }
    }

    func writeByte(_ byte: UInt8) {
        flush()
        self.data.append(byte)
    }
}

class BitReader {
    private let data: Data
    private var offset: Int
    private var cache: UInt8
    private var bits: UInt8

    init(data: Data) {
        self.data = data
        self.offset = 0
        self.cache = 0
        self.bits = 0
    }

    func readBit() throws -> UInt8 {
        if self.bits == 0 {
            if self.data.count <= self.offset {
                throw BitError.eoF
            }
            self.cache = self.data[self.offset]
            self.offset += 1
            self.bits = 8
        }
        self.bits -= 1
        let bit = (self.cache >> self.bits) & 1
        return bit
    }

    func readBits(n: UInt8) throws -> UInt16 {
        var val: UInt16 = 0
        for _ in 0..<n {
            let bit = try readBit()
            val = (val << 1) | UInt16(bit)
        }
        return val
    }
}

class RiceWriter<T: UnsignedInteger> {
    let bw: BitWriter

    init(bw: BitWriter) {
        self.bw = bw
    }

    func write(val: T, k: UInt8) {
        let m = T(1) << k
        let q = val / m
        let r = val % m

        let qLimit = Int(q)
        for _ in 0..<qLimit {
            self.bw.writeBit(1)
        }
        self.bw.writeBit(0)

        self.bw.writeBits(val: UInt16(r), n: k)
    }

    func flush() {
        self.bw.flush()
    }
}

class RiceReader<T: UnsignedInteger> {
    let br: BitReader

    init(br: BitReader) {
        self.br = br
    }

    func readRice(k: UInt8) throws -> T {
        var q: T = 0
        // Read unary
        while true {
            let bit = try self.br.readBit()
            if bit == 0 {
                break
            }
            q += 1
        }

        // Read remainder
        let rem64 = try self.br.readBits(n: k)
        let rem = T(rem64)

        let val = (q << k) | rem
        return val
    }
}
