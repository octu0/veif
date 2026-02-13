import Foundation

public class RateController {
    public let maxbit: Int
    public let totalProcessPixels: Int
    public var currentBits: Int
    public var processedPixels: Int
    public var baseShift: Int
    
    public init(maxbit: Int, totalProcessPixels: Int, baseShift: Int = 2) {
        self.maxbit = maxbit
        self.totalProcessPixels = totalProcessPixels
        self.currentBits = 0
        self.processedPixels = 0
        self.baseShift = baseShift
    }
    
    public func calcScale(addedBits: Int, addedPixels: Int) -> Int {
        currentBits += addedBits
        processedPixels += addedPixels
        
        let targetBitsProgress = (Double(maxbit) * (Double(processedPixels) / Double(totalProcessPixels)))
        
        if 0 < targetBitsProgress {
            let overshoot = (Double(currentBits) / targetBitsProgress)
            if 2.0 < overshoot {
                baseShift += 2
            } else {
                if 1.3 < overshoot {
                    baseShift += 1
                } else {
                    if overshoot < 0.5 && 0 < baseShift {
                        baseShift -= 2
                    } else {
                        if overshoot < 0.8 && 0 < baseShift {
                            baseShift -= 1
                        }
                    }
                }
            }
        }
        
        if baseShift < 0 {
            baseShift = 0
        }
        if 5 < baseShift {
            baseShift = 5
        }
        
        return baseShift
    }
}

public typealias RowFunc = (_ x: Int, _ y: Int, _ size: Int) -> [Int16]

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
