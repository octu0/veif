import Foundation

class RateController {
    let maxbit: Int
    let totalProcessPixels: Int
    var currentBits: Int
    var processedPixels: Int
    var baseShift: Int
    
    init(maxbit: Int, width: Int, height: Int) {
        self.maxbit = maxbit
        let totalPixels = width * height
        self.totalProcessPixels = totalPixels + (totalPixels / 2)
        self.currentBits = 0
        self.processedPixels = 0
        self.baseShift = 0
    }
    
    func calcScale(addedBits: Int, addedPixels: Int) -> Int {
        self.currentBits += addedBits
        self.processedPixels += addedPixels
        
        // Target bits progress
        let targetBitsProgress = Int(Double(self.maxbit) * (Double(self.processedPixels) / Double(self.totalProcessPixels)))
        
        let diff = self.currentBits - targetBitsProgress
        let threshold = self.maxbit / 10
        
        if threshold < diff {
            self.baseShift += 1
            self.currentBits -= threshold / 2
        } else if diff < -1 * threshold {
            if 0 < self.baseShift {
                self.baseShift -= 1
                self.currentBits += threshold / 2
            }
        }
        
        if self.baseShift < 0 {
            self.baseShift = 0
        }
        if 8 < self.baseShift {
            self.baseShift = 8
        }
        
        return self.baseShift
    }
}
