import JavaScriptKit
import JavaScriptEventLoop
import veif

JavaScriptEventLoop.installGlobalExecutor()

@JS
func encodeVeif(data: JSObject, width: Int, height: Int, bitrate: Int) -> JSObject {
    return JSPromise.async { () async throws(JSException) -> JSValue in
        let typedArray = JSTypedArray<UInt8>(unsafelyWrapping: data)
        let localData: [UInt8] = typedArray.withUnsafeBytes { ptr in
            Array(ptr)
        }
        
        let ycbcr = rgbaToYCbCr(data: localData, width: width, height: height)
        let out: [UInt8]
        do {
            out = try await veif.encodeOne(img: ycbcr, maxbitrate: bitrate)
        } catch {
            throw JSException(message: String(describing: error))
        }
        
        let result = out.withUnsafeBytes { buf in
            JSTypedArray<UInt8>(buffer: buf.bindMemory(to: UInt8.self))
        }
        return result.jsValue
    }.jsObject
}

@JS
func decodeVeif(data: JSObject) -> JSObject {
    return JSPromise.async { () async throws(JSException) -> JSValue in
        let typedArray = JSTypedArray<UInt8>(unsafelyWrapping: data)
        let localData: [UInt8] = typedArray.withUnsafeBytes { ptr in
            Array(ptr)
        }
        
        let img: YCbCrImage
        do {
            img = try await veif.decodeOne(r: localData)
        } catch {
            throw JSException(message: String(describing: error))
        }
        let rgba = ycbcrToRGBA(img: img)
        
        let jsArr = rgba.withUnsafeBytes { buf in
            JSTypedArray<UInt8>(buffer: buf.bindMemory(to: UInt8.self))
        }
        
        let resultObj = JSObject.global.Object.function!.new()
        resultObj.data = jsArr.jsValue
        resultObj.width = .number(Double(img.width))
        resultObj.height = .number(Double(img.height))
        
        return resultObj.jsValue
    }.jsObject
}



func rgbaToYCbCr(data: [UInt8], width: Int, height: Int) -> YCbCrImage {
    var ycbcr = YCbCrImage(width: width, height: height, ratio: .ratio444)
    let bytesPerPixel = 4
    let bytesPerRow = (bytesPerPixel * width)
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = ((y * bytesPerRow) + (x * bytesPerPixel))
            let r1 = Int32(data[offset + 0])
            let g1 = Int32(data[offset + 1])
            let b1 = Int32(data[offset + 2])
            
            let yVal = (19595 * r1 + 38470 * g1 + 7471 * b1 + (1 << 15)) >> 16
            let cbVal = ((-11059 * r1 - 21709 * g1 + 32768 * b1 + (1 << 15)) >> 16) + 128
            let crVal = ((32768 * r1 - 27439 * g1 - 5329 * b1 + (1 << 15)) >> 16) + 128
            
            let yIdx = ycbcr.yOffset(x, y)
            ycbcr.yPlane[yIdx] = UInt8(clamping: yVal)
            
            let cOff = ycbcr.cOffset(x, y)
            if cOff < ycbcr.cbPlane.count {
                ycbcr.cbPlane[cOff] = UInt8(clamping: cbVal)
                ycbcr.crPlane[cOff] = UInt8(clamping: crVal)
            }
        }
    }
    
    return ycbcr
}

func ycbcrToRGBA(img: YCbCrImage) -> [UInt8] {
    let width = img.width
    let height = img.height
    let bytesPerPixel = 4
    let bytesPerRow = (bytesPerPixel * width)
    var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
    
    for y in 0..<height {
        for x in 0..<width {
            let yVal = Int(img.yPlane[img.yOffset(x, y)]) << 10
            
            var cPx = x
            var cPy = y
            if img.ratio == .ratio420 {
                cPx = (x / 2)
                cPy = (y / 2)
            }
            
            let cOff = img.cOffset(cPx, cPy)
            let cbDiff = Int(img.cbPlane[cOff]) - 128
            let crDiff = Int(img.crPlane[cOff]) - 128
            
            let r = (yVal + (1436 * crDiff)) >> 10
            let g = (yVal - (352 * cbDiff) - (731 * crDiff)) >> 10
            let b = (yVal + (1815 * cbDiff)) >> 10
            
            let offset = ((y * bytesPerRow) + (x * bytesPerPixel))
            rawData[offset + 0] = UInt8(clamping: r)
            rawData[offset + 1] = UInt8(clamping: g)
            rawData[offset + 2] = UInt8(clamping: b)
            rawData[offset + 3] = 255 // Alpha
        }
    }
    
    return rawData
}
