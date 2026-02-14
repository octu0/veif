
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

    public mutating func setRow(offsetY: Int, size: Int, row: [Int16]) {
        let offset = self.rowOffset(y: offsetY)
        for i in 0..<size {
            self.data[offset + i] = row[i]
        }
    }
}
