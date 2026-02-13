import Foundation

public struct Scale {
    public var minVal: Int16
    public var maxVal: Int16
    public let rowFn: RowFunc
    
    public init(rowFn: @escaping RowFunc) {
        self.minVal = Int16.max
        self.maxVal = Int16.min
        self.rowFn = rowFn
    }
    
    public mutating func rows(w: Int, h: Int, size: Int, baseShift: Int) -> (Block2D, Int) {
        var block = Block2D(width: size, height: size)
        self.minVal = Int16.max
        self.maxVal = Int16.min
        
        for i in 0..<size {
            let r = rowFn(w, (h + i), size)
            let offset = block.rowOffset(y: i)
            for j in 0..<size {
                block.data[offset + j] = r[j]
                let v = r[j]
                if v < minVal {
                    minVal = v
                }
                if maxVal < v {
                    maxVal = v
                }
            }
        }
        
        let localScale = baseShift
        return (block, localScale)
    }
}
