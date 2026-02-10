// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "veif",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "veif", targets: ["veif"]),
    ],
    targets: [
        .target(
            name: "veif",
            dependencies: []
        ),
        .executableTarget(
            name: "example",
            dependencies: ["veif"]
        ),
        .testTarget(
            name: "veifTests",
            dependencies: ["veif"]
        ),
    ],
    swiftLanguageModes: [.v6],
)
