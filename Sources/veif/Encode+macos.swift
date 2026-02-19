#if os(macOS)
import Foundation

public func encodeImage(img: YCbCrImage, maxbitrate: Int) async throws -> Data {
    let bytes = try await encode(img: img, maxbitrate: maxbitrate)
    return Data(bytes)
}

public func encodeImageLayers(img: YCbCrImage, maxbitrate: Int) async throws -> (Data, Data, Data) {
    let (l0, l1, l2) = try await encodeLayers(img: img, maxbitrate: maxbitrate)
    return (Data(l0), Data(l1), Data(l2))
}

public func encodeImageOne(img: YCbCrImage, maxbitrate: Int) async throws -> Data {
    let bytes = try await encodeOne(img: img, maxbitrate: maxbitrate)
    return Data(bytes)
}

#endif