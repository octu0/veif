import Foundation

// MARK: - Metric Utils

public struct BenchmarkMetrics {
    public let psnr: Double
    public let psnrY: Double
    public let psnrC: Double // Cb
    public let psnrK: Double // Cr
    
    public let ssim: Double
    public let msssim: Double
    
    public let y: Double
    public let cb: Double
    public let cr: Double
}

func extractPlanes(_ img: YCbCrImage) -> ([[Double]], [[Double]], [[Double]]) {
    let w = img.width
    let h = img.height
    
    var yPlane = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)
    var cbPlane = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)
    var crPlane = [[Double]](repeating: [Double](repeating: 0, count: w), count: h)
    
    for y in 0..<h {
        for x in 0..<w {
            yPlane[y][x] = Double(img.yPlane[img.yOffset(x, y)])
            
            var cPx = x
            var cPy = y
            if img.ratio == .ratio420 {
                cPx = (x / 2)
                cPy = (y / 2)
            }
            let cOff = img.cOffset(cPx, cPy)
            cbPlane[y][x] = Double(img.cbPlane[cOff])
            crPlane[y][x] = Double(img.crPlane[cOff])
        }
    }
    return (yPlane, cbPlane, crPlane)
}

public func calcPSNR(img1: YCbCrImage, img2: YCbCrImage) -> (Double, Double, Double, Double) {
    let w = img1.width
    let h = img1.height
    
    var mseY = 0.0
    var mseCb = 0.0
    var mseCr = 0.0
    
    for y in 0..<h {
        for x in 0..<w {
            let y1 = Double(img1.yPlane[img1.yOffset(x, y)])
            
            var cPx1 = x
            var cPy1 = y
            if img1.ratio == .ratio420 {
                cPx1 = (x / 2)
                cPy1 = (y / 2)
            }
            let cOff1 = img1.cOffset(cPx1, cPy1)
            let cb1 = Double(img1.cbPlane[cOff1])
            let cr1 = Double(img1.crPlane[cOff1])
            
            let y2 = Double(img2.yPlane[img2.yOffset(x, y)])
            
            var cPx2 = x
            var cPy2 = y
            if img2.ratio == .ratio420 {
                cPx2 = (x / 2)
                cPy2 = (y / 2)
            }
            let cOff2 = img2.cOffset(cPx2, cPy2)
            let cb2 = Double(img2.cbPlane[cOff2])
            let cr2 = Double(img2.crPlane[cOff2])
            
            let dy = (y1 - y2)
            let dcb = (cb1 - cb2)
            let dcr = (cr1 - cr2)
            
            mseY += (dy * dy)
            mseCb += (dcb * dcb)
            mseCr += (dcr * dcr)
        }
    }
    
    let pixels = Double(w * h)
    mseY /= pixels
    mseCb /= pixels
    mseCr /= pixels
    
    var psnrY = (20 * log10(255.0 / sqrt(mseY)))
    var psnrCb = (20 * log10(255.0 / sqrt(mseCb)))
    var psnrCr = (20 * log10(255.0 / sqrt(mseCr)))
    
    if mseY == 0 { psnrY = 100.0 }
    if mseCb == 0 { psnrCb = 100.0 }
    if mseCr == 0 { psnrCr = 100.0 }
    
    let avg = ((psnrY + psnrCb + psnrCr) / 3.0)
    return (psnrY, psnrCb, psnrCr, avg)
}

// MARK: - SSIM

public func calcSSIM(img1: YCbCrImage, img2: YCbCrImage) -> (Double, Double, Double, Double) {
    let c1 = ((0.01 * 0.01) * (255 * 255))
    let c2 = ((0.03 * 0.03) * (255 * 255))
    
    let (y1, cb1, cr1) = extractPlanes(img1)
    let (y2, cb2, cr2) = extractPlanes(img2)
    
    let ssimY = ssimPlane(p1: y1, p2: y2, c1: c1, c2: c2)
    let ssimCb = ssimPlane(p1: cb1, p2: cb2, c1: c1, c2: c2)
    let ssimCr = ssimPlane(p1: cr1, p2: cr2, c1: c1, c2: c2)
    
    return (ssimY, ssimCb, ssimCr, ((ssimY + ssimCb + ssimCr) / 3.0))
}

func ssimPlane(p1: [[Double]], p2: [[Double]], c1: Double, c2: Double) -> Double {
    let h = p1.count
    let w = p1[0].count
    let blockSize = 8
    
    var totalSSIM = 0.0
    var count = 0
    
    for y in stride(from: 0, to: (h - blockSize), by: blockSize) {
        for x in stride(from: 0, to: (w - blockSize), by: blockSize) {
            totalSSIM += ssimBlock(p1: p1, p2: p2, x: x, y: y, size: blockSize, c1: c1, c2: c2)
            count += 1
        }
    }
    
    if count == 0 {
        return 0
    }
    return (totalSSIM / Double(count))
}

func ssimBlockComponents(p1: [[Double]], p2: [[Double]], x: Int, y: Int, size: Int, c1: Double, c2: Double) -> (Double, Double) {
    var mu1 = 0.0
    var mu2 = 0.0
    
    for j in 0..<size {
        for i in 0..<size {
            mu1 += p1[y + j][x + i]
            mu2 += p2[y + j][x + i]
        }
    }
    
    let n = Double(size * size)
    mu1 /= n
    mu2 /= n
    
    var sigma1Sq = 0.0
    var sigma2Sq = 0.0
    var sigma12 = 0.0
    
    for j in 0..<size {
        for i in 0..<size {
            let d1 = (p1[y + j][x + i] - mu1)
            let d2 = (p2[y + j][x + i] - mu2)
            sigma1Sq += (d1 * d1)
            sigma2Sq += (d2 * d2)
            sigma12 += (d1 * d2)
        }
    }
    
    sigma1Sq /= (n - 1)
    sigma2Sq /= (n - 1)
    sigma12 /= (n - 1)
    
    let lNum = ((2 * mu1 * mu2) + c1)
    let lDen = ((mu1 * mu1) + (mu2 * mu2) + c1)
    
    let csNum = ((2 * sigma12) + c2)
    let csDen = ((sigma1Sq + sigma2Sq) + c2)
    
    return ((lNum / lDen), (csNum / csDen))
}

func ssimBlock(p1: [[Double]], p2: [[Double]], x: Int, y: Int, size: Int, c1: Double, c2: Double) -> Double {
    let (l, cs) = ssimBlockComponents(p1: p1, p2: p2, x: x, y: y, size: size, c1: c1, c2: c2)
    return (l * cs)
}

// MARK: - MS-SSIM

public func calcMSSSIM(img1: YCbCrImage, img2: YCbCrImage) -> (Double, Double, Double, Double) {
    let weights = [0.0448, 0.2856, 0.3001, 0.2363, 0.1333]
    let levels = weights.count
    
    let c1 = ((0.01 * 0.01) * (255 * 255))
    let c2 = ((0.03 * 0.03) * (255 * 255))
    
    let (y1, cb1, cr1) = extractPlanes(img1)
    let (y2, cb2, cr2) = extractPlanes(img2)
    
    let msssimY = msssimPlane(p1: y1, p2: y2, weights: weights, levels: levels, c1: c1, c2: c2)
    let msssimCb = msssimPlane(p1: cb1, p2: cb2, weights: weights, levels: levels, c1: c1, c2: c2)
    let msssimCr = msssimPlane(p1: cr1, p2: cr2, weights: weights, levels: levels, c1: c1, c2: c2)
    
    return (msssimY, msssimCb, msssimCr, ((msssimY + msssimCb + msssimCr) / 3.0))
}

func downsamplePlane(_ p: [[Double]]) -> [[Double]] {
    let h = p.count
    let w = p[0].count
    let newH = (h / 2)
    let newW = (w / 2)
    
    var newP = [[Double]](repeating: [Double](repeating: 0, count: newW), count: newH)
    for y in 0..<newH {
        for x in 0..<newW {
            let sum = (((p[y * 2][x * 2] + p[y * 2][x * 2 + 1]) + p[y * 2 + 1][x * 2]) + p[y * 2 + 1][x * 2 + 1])
            newP[y][x] = (sum / 4.0)
        }
    }
    return newP
}

func ssimComponents(p1: [[Double]], p2: [[Double]], c1: Double, c2: Double) -> (Double, Double) {
    let h = p1.count
    let w = p1[0].count
    let blockSize = 8
    
    var totalL = 0.0
    var totalCS = 0.0
    var count = 0
    
    for y in stride(from: 0, to: (h - blockSize), by: blockSize) {
        for x in stride(from: 0, to: (w - blockSize), by: blockSize) {
            let (l, cs) = ssimBlockComponents(p1: p1, p2: p2, x: x, y: y, size: blockSize, c1: c1, c2: c2)
            totalL += l
            totalCS += cs
            count += 1
        }
    }
    
    if count == 0 {
        return (0, 0)
    }
    return ((totalL / Double(count)), (totalCS / Double(count)))
}

func msssimPlane(p1: [[Double]], p2: [[Double]], weights: [Double], levels: Int, c1: Double, c2: Double) -> Double {
    var finalScore = 1.0
    
    var currP1 = p1
    var currP2 = p2
    
    for i in 0..<levels {
        let (l, cs) = ssimComponents(p1: currP1, p2: currP2, c1: c1, c2: c2)
        
        if i < (levels - 1) {
            if 0 < cs {
                finalScore *= pow(cs, weights[i])
            }
        } else {
            if 0 < l {
                finalScore *= pow(l, weights[i])
            }
            if 0 < cs {
                finalScore *= pow(cs, weights[i])
            }
        }
        
        if i < (levels - 1) {
            currP1 = downsamplePlane(currP1)
            currP2 = downsamplePlane(currP2)
        }
    }
    return finalScore
}

public func calcMetrics(ref: YCbCrImage, target: YCbCrImage) -> BenchmarkMetrics {
    let (psnrY, psnrCb, psnrCr, avgPSNR) = calcPSNR(img1: ref, img2: target)
    let (ssimY, ssimCb, ssimCr, avgSSIM) = calcSSIM(img1: ref, img2: target)
    let (_, _, _, avgMSSSIM) = calcMSSSIM(img1: ref, img2: target)
    
    return BenchmarkMetrics(
        psnr: avgPSNR,
        psnrY: psnrY,
        psnrC: psnrCb,
        psnrK: psnrCr,
        ssim: avgSSIM,
        msssim: avgMSSSIM,
        y: ssimY,
        cb: ssimCb,
        cr: ssimCr
    )
}

public func resizeHalfNN(_ src: YCbCrImage) -> YCbCrImage {
    let w = src.width
    let h = src.height
    let dstW = (w / 2)
    let dstH = (h / 2)
    
    var dst = YCbCrImage(width: dstW, height: dstH)
    
    // Resize Y
    for y in 0..<dstH {
        for x in 0..<dstW {
            let sy = (y * 2)
            let sx = (x * 2)
            dst.yPlane[dst.yOffset(x, y)] = src.yPlane[src.yOffset(sx, sy)]
        }
    }
    
    let dstCW = (dstW / 2)
    let dstCH = (dstH / 2)
    
    for y in 0..<dstCH {
        for x in 0..<dstCW {
            let dOff = dst.cOffset(x, y)
            
            var sPx = (x * 2)
            var sPy = (y * 2)
            if src.ratio == .ratio444 {
                sPx = (x * 4)
                sPy = (y * 4)
            }
            
            let sOff = src.cOffset(sPx, sPy)
            if sOff < src.cbPlane.count {
                dst.cbPlane[dOff] = src.cbPlane[sOff]
                dst.crPlane[dOff] = src.crPlane[sOff]
            }
        }
    }
    
    return dst
}
