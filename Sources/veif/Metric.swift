import Foundation

func calcPSNR(img1: Image16, img2: Image16) -> (Double, Double, Double, Double) {
    let w = img1.width
    let h = img1.height
    
    if img2.width != w || img2.height != h {
        return (0, 0, 0, 0)
    }
    
    var mseY: Double = 0
    var mseCb: Double = 0
    var mseCr: Double = 0
    
    // Y
    for i in 0..<img1.yPlane.count {
        let diff = Double(img1.yPlane[i]) - Double(img2.yPlane[i])
        mseY += diff * diff
    }
    
    // Cb
    for i in 0..<img1.cbPlane.count {
        let diff = Double(img1.cbPlane[i]) - Double(img2.cbPlane[i])
        mseCb += diff * diff
    }
    
    // Cr
    for i in 0..<img1.crPlane.count {
        let diff = Double(img1.crPlane[i]) - Double(img2.crPlane[i])
        mseCr += diff * diff
    }
    
    let pixels = Double(w * h)
    mseY /= pixels
    mseCb /= pixels
    mseCr /= pixels
    
    func psnr(_ mse: Double) -> Double {
        if mse == 0 { return 100.0 }
        return 20 * log10(255.0 / sqrt(mse))
    }
    
    let psnrY = psnr(mseY)
    let psnrCb = psnr(mseCb)
    let psnrCr = psnr(mseCr)
    
    let avg = (psnrY + psnrCb + psnrCr) / 3.0
    return (psnrY, psnrCb, psnrCr, avg)
}
