#if os(macOS)
import Foundation

public func decodeImage(r: Data) async throws -> (YCbCrImage, YCbCrImage, YCbCrImage) {
    let bytes = [UInt8](r)
    return try await decode(r: bytes)
}

public func decodeImageLayer0(r: Data) async throws -> YCbCrImage {
    let bytes = [UInt8](r)
    return try await decodeLayer0(r: bytes)
}

public func decodeImageOne(r: Data) async throws -> YCbCrImage {
    let bytes = [UInt8](r)
    return try await decodeOne(r: bytes)
}

public func decodeImageLayers(data: Data...) async throws -> YCbCrImage {
    let bytesArrays = data.map { [UInt8]($0) }
    guard let base = bytesArrays.first else {
        throw DecodeError.noDataProvided
    }
    
    var current = try await decodeBase(r: base, layer: 0, size: 8)
    var currentSize = 16
    
    for i in 1..<bytesArrays.count {
        current = try await decodeLayer(r: bytesArrays[i], layer: UInt8(i), prev: current, size: currentSize)
        currentSize *= 2
    }
    
    return current.toYCbCr()
}

#endif
