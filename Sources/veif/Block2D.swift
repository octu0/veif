import Foundation

// MARK: - Block2D

public struct Block2D: Sendable {
    public var data: [Int16]
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = [Int16](repeating: 0, count: (width * height))
    }

    @inline(__always)
    public subscript(y: Int, x: Int) -> Int16 {
        get { data[(y * width) + x] }
        set { data[(y * width) + x] = newValue }
    }

    @inline(__always)
    public func rowOffset(y: Int) -> Int {
        return (y * width)
    }

    @inline(__always)
    public mutating func setRow(offsetY: Int, size: Int, row: [Int16]) {
        let offset = self.rowOffset(y: offsetY)
        row.withUnsafeBufferPointer { ptr in
            self.data.withUnsafeMutableBufferPointer { dest in
                let destPtr = dest.baseAddress!.advanced(by: offset)
                let srcPtr = ptr.baseAddress!
                memcpy(destPtr, srcPtr, size * MemoryLayout<Int16>.size)
            }
        }
    }

    @inline(__always)
    public func withUnsafeBufferPointer<R>(atRow y: Int, body: (UnsafeBufferPointer<Int16>) throws -> R) rethrows -> R {
        let offset = self.rowOffset(y: y)
        return try self.data.withUnsafeBufferPointer { ptr in
            let rowStart = ptr.baseAddress!.advanced(by: offset)
            let rowBuffer = UnsafeBufferPointer(start: rowStart, count: self.width)
            return try body(rowBuffer)
        }
    }
}
