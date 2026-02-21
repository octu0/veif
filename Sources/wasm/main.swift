import JavaScriptKit
import JavaScriptEventLoop
import veif

JavaScriptEventLoop.installGlobalExecutor()

// Helper to create JS object from image data
func makeImageObject(width: Int, height: Int, data: [UInt8]) -> JSValue {
    let jsArr = data.withUnsafeBytes { buf in
        JSTypedArray<UInt8>(buffer: buf.bindMemory(to: UInt8.self))
    }
    
    let resultObj = JSObject()
    resultObj.data = jsArr.jsValue
    resultObj.width = .number(Double(width))
    resultObj.height = .number(Double(height))
    return resultObj.jsValue
}

@JS
func encodeOne(data: JSValue, width: Int, height: Int, bitrate: Int, onSuccess: JSObject, onError: JSObject) {
    guard let object = data.object, let typedArray = JSTypedArray<UInt8>(from: object.jsValue) else {
        _ = onError.callAsFunction("Input is not a valid typed array")
        return
    }
    var localData = [UInt8](repeating: 0, count: typedArray.length)
    localData.withUnsafeMutableBufferPointer { ptr in
        typedArray.copyMemory(to: ptr)
    }
    
    struct Callbacks: @unchecked Sendable {
        let onSuccess: JSObject
        let onError: JSObject
    }
    let callbacks = Callbacks(onSuccess: onSuccess, onError: onError)
    
    Task {
        let ycbcr = veif.rgbaToYCbCr(data: localData, width: width, height: height)
        let out: [UInt8]
        do {
            out = try await veif.encodeOne(img: ycbcr, maxbitrate: bitrate)
        } catch {
            _ = callbacks.onError.callAsFunction(String(describing: error))
            return
        }
        
        let result = out.withUnsafeBytes { buf in
            JSTypedArray<UInt8>(buffer: buf.bindMemory(to: UInt8.self))
        }
        _ = callbacks.onSuccess.callAsFunction(result)
    }
}

@JS
func decodeOne(data: JSValue, onSuccess: JSObject, onError: JSObject) {
    guard let object = data.object, let typedArray = JSTypedArray<UInt8>(from: object.jsValue) else {
        _ = onError.callAsFunction("Input is not a valid typed array")
        return
    }
    var localData = [UInt8](repeating: 0, count: typedArray.length)
    localData.withUnsafeMutableBufferPointer { ptr in
        typedArray.copyMemory(to: ptr)
    }
    
    struct Callbacks: @unchecked Sendable {
        let onSuccess: JSObject
        let onError: JSObject
    }
    let callbacks = Callbacks(onSuccess: onSuccess, onError: onError)
    
    Task {
        let img: YCbCrImage
        do {
            img = try await veif.decodeOne(r: localData)
        } catch {
            _ = callbacks.onError.callAsFunction(String(describing: error))
            return
        }
        let rgba = veif.ycbcrToRGBA(img: img)
        _ = callbacks.onSuccess.callAsFunction(makeImageObject(width: img.width, height: img.height, data: rgba))
    }
}

@JS
func encode(data: JSValue, width: Int, height: Int, bitrate: Int, onSuccess: JSObject, onError: JSObject) {
    guard let object = data.object, let typedArray = JSTypedArray<UInt8>(from: object.jsValue) else {
        _ = onError.callAsFunction("Input is not a valid typed array")
        return
    }
    var localData = [UInt8](repeating: 0, count: typedArray.length)
    localData.withUnsafeMutableBufferPointer { ptr in
        typedArray.copyMemory(to: ptr)
    }
    
    struct Callbacks: @unchecked Sendable {
        let onSuccess: JSObject
        let onError: JSObject
    }
    let callbacks = Callbacks(onSuccess: onSuccess, onError: onError)
    
    Task {
        let ycbcr = veif.rgbaToYCbCr(data: localData, width: width, height: height)
        let out: [UInt8]
        do {
            out = try await veif.encode(img: ycbcr, maxbitrate: bitrate)
        } catch {
            _ = callbacks.onError.callAsFunction(String(describing: error))
            return
        }
        
        let result = out.withUnsafeBytes { buf in
            JSTypedArray<UInt8>(buffer: buf.bindMemory(to: UInt8.self))
        }
        _ = callbacks.onSuccess.callAsFunction(result)
    }
}

@JS
func decode(data: JSValue, onSuccess: JSObject, onError: JSObject) {
    guard let object = data.object, let typedArray = JSTypedArray<UInt8>(from: object.jsValue) else {
        _ = onError.callAsFunction("Input is not a valid typed array")
        return
    }
    var localData = [UInt8](repeating: 0, count: typedArray.length)
    localData.withUnsafeMutableBufferPointer { ptr in
        typedArray.copyMemory(to: ptr)
    }
    
    struct Callbacks: @unchecked Sendable {
        let onSuccess: JSObject
        let onError: JSObject
    }
    let callbacks = Callbacks(onSuccess: onSuccess, onError: onError)
    
    Task {
        let layers: (YCbCrImage, YCbCrImage, YCbCrImage)
        do {
            layers = try await veif.decode(r: localData)
        } catch {
            _ = callbacks.onError.callAsFunction(String(describing: error))
            return
        }
        
        let (l0, l1, l2) = layers
        let rgba0 = ycbcrToRGBA(img: l0)
        let rgba1 = ycbcrToRGBA(img: l1)
        let rgba2 = ycbcrToRGBA(img: l2)
        
        let resultObj = JSObject()
        resultObj.layer0 = makeImageObject(width: l0.width, height: l0.height, data: rgba0)
        resultObj.layer1 = makeImageObject(width: l1.width, height: l1.height, data: rgba1)
        resultObj.layer2 = makeImageObject(width: l2.width, height: l2.height, data: rgba2)
        
        _ = callbacks.onSuccess.callAsFunction(resultObj)
    }
}

@JS
func decodeUpTo(data: JSValue, maxLayer: Int, onSuccess: JSObject, onError: JSObject) {
    guard let object = data.object, let typedArray = JSTypedArray<UInt8>(from: object.jsValue) else {
        _ = onError.callAsFunction("Input is not a valid typed array")
        return
    }
    var localData = [UInt8](repeating: 0, count: typedArray.length)
    localData.withUnsafeMutableBufferPointer { ptr in
        typedArray.copyMemory(to: ptr)
    }
    
    struct Callbacks: @unchecked Sendable {
        let onSuccess: JSObject
        let onError: JSObject
    }
    let callbacks = Callbacks(onSuccess: onSuccess, onError: onError)
    
    Task {
        let img: YCbCrImage
        do {
            img = try await veif.decodeLayers(r: localData, maxLayer: maxLayer)
        } catch {
            _ = callbacks.onError.callAsFunction(String(describing: error))
            return
        }
        let rgba = veif.ycbcrToRGBA(img: img)
        _ = callbacks.onSuccess.callAsFunction(makeImageObject(width: img.width, height: img.height, data: rgba))
    }
}