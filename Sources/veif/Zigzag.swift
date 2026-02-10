import Foundation

func zigzag<T>(data: UnsafeBufferPointer<T>, size: Int, into result: UnsafeMutableBufferPointer<T>)
where T: SignedInteger {
    let table = getZigzagTable(size: size)

    for (i, c) in table.enumerated() {
        let r = Int(c.r)
        let c = Int(c.c)
        let idx = r * size + c
        if idx < data.count {
            if i < result.count {
                result[i] = data[idx]
            }
        }
    }
}

func unzigzag<C>(data: C, size: Int, into result: UnsafeMutableBufferPointer<C.Element>)
where
    C: RandomAccessCollection,
    C.Element: SignedInteger,
    C.Index == Int
{
    let table = getZigzagTable(size: size)

    for (i, c) in table.enumerated() {
        if i < data.count {
            let idx = Int(c.r) * size + Int(c.c)
            if idx < result.count {
                result[idx] = data[data.startIndex + i]
            }
        }
    }
}
