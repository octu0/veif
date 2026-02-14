import Foundation

// MARK: - Block2D

public class Block2D: @unchecked Sendable {
    public var data: [Int16]
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = [Int16](repeating: 0, count: (width * height))
    }

    /// data[y][x] 相当のアクセス
    @inline(__always)
    public subscript(y: Int, x: Int) -> Int16 {
        get { data[(y * width) + x] }
        set { data[(y * width) + x] = newValue }
    }

    /// 行の開始インデックス
    @inline(__always)
    public func rowOffset(y: Int) -> Int {
        return (y * width)
    }

    public func setRow(offsetY: Int, size: Int, row: [Int16]) {
        let offset = self.rowOffset(y: offsetY)
        row.withUnsafeBufferPointer { ptr in
            self.data.withUnsafeMutableBufferPointer { dest in
                let destPtr = dest.baseAddress!.advanced(by: offset)
                let srcPtr = ptr.baseAddress!
                memcpy(destPtr, srcPtr, size * MemoryLayout<Int16>.size)
            }
        }
    }
}
