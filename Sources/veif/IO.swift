import Foundation

class BinaryReader {
    let data: Data
    var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    func read<T: FixedWidthInteger>(as type: T.Type, bigEndian: Bool = true) throws -> T {
        let size = MemoryLayout<T>.size

        guard offset + size <= data.count else {
            throw NSError(domain: "BinaryReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "EOF"])
        }

        let value = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: T.self)
        }

        offset += size

        return bigEndian ? T(bigEndian: value) : T(littleEndian: value)
    }

    func readBytes(_ n: Int) -> Data {
        let sub = data.subdata(in: offset..<offset + n)
        offset += n
        return sub
    }

    func seek(to newOffset: Int) {
        self.offset = newOffset
    }
}

class BinaryWriter {
    var data: Data

    init() {
        self.data = Data()
    }

    func write<T: FixedWidthInteger>(_ value: T, bigEndian: Bool = true) {
        var v = bigEndian ? value.bigEndian : value.littleEndian
        withUnsafeBytes(of: &v) {
            data.append($0.bindMemory(to: UInt8.self))
        }
    }

    func append(_ d: Data) {
        data.append(d)
    }

    func append(contentsOf d: [UInt8]) {
        data.append(contentsOf: d)
    }
}
