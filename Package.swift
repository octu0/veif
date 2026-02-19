// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "veif",
    products: [
        .library(name: "veif", targets: ["veif"]),
        .executable(name: "wasm", targets: ["wasm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.45.0")
    ],
    targets: [
        .target(
            name: "veif",
            dependencies: [],
        ),
        .executableTarget(
            name: "example",
            dependencies: ["veif"],
            //swiftSettings:[.unsafeFlags(["-whole-module-optimization"])]
        ),
        .executableTarget(
            name: "wasm",
            dependencies: [
                "veif",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit")
            ],
            swiftSettings: [
                .enableExperimentalFeature("Extern")
            ],
            plugins: [
                .plugin(name: "BridgeJS", package: "JavaScriptKit")
            ]
        ),
        .testTarget(
            name: "veifTests",
            dependencies: ["veif"]
        ),
    ],
    swiftLanguageModes: [.v6],
)
