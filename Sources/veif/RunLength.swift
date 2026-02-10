import Foundation

let BlockKeyK: UInt8 = 1
let BlockValueK: UInt8 = 15

func blockRLEEncode(rw: RiceWriter<UInt16>, data: [UInt16]) {
    if data.isEmpty {
        return
    }
    
    var currentVal = data[0]
    var currentLen: UInt16 = 1
    
    for i in 1..<data.count {
        let v = data[i]
        if v != currentVal || currentLen == 65535 {
            rw.write(val: currentLen, k: BlockKeyK)
            rw.write(val: currentVal, k: BlockValueK)
            currentVal = v
            currentLen = 1
        } else {
            currentLen += 1
        }
    }
    
    rw.write(val: currentLen, k: BlockKeyK)
    rw.write(val: currentVal, k: BlockValueK)
}

func blockRLEDecode(rr: RiceReader<UInt16>, size: Int) throws -> [UInt16] {
    var out: [UInt16] = []
    out.reserveCapacity(size)
    
    while out.count < size {
        let lenVal = try rr.readRice(k: BlockKeyK)
        let valVal = try rr.readRice(k: BlockValueK)
        
        for _ in 0..<lenVal {
            out.append(valVal)
        }
    }
    return out
}
