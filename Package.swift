// swift-tools-version: 6.0
import PackageDescription
import Foundation

let isWasmBuild = ProcessInfo.processInfo.environment["WASM_BUILD"] == "1"

var packageProducts: [Product] = [
    .library(name: "veif", targets: ["veif"]),
]

var packageDeps: [Package.Dependency] = []

var packageTargets: [Target] = [
    .target(
        name: "veif",
        dependencies: [],
        swiftSettings: [
            .unsafeFlags(["-Ounchecked", "-wmo", "-Xcc", "-msimd128"], .when(platforms: [.wasi]))
        ]
    ),
    .executableTarget(
        name: "example",
        dependencies: ["veif"],
        //swiftSettings:[.unsafeFlags(["-whole-module-optimization"])]
    ),
    .testTarget(
        name: "veifTests",
        dependencies: ["veif"]
    ),
]

if isWasmBuild {
    packageDeps.append(.package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.45.0"))
    packageProducts.append(.executable(name: "wasm", targets: ["wasm"]))
    
    packageTargets.append(
        .executableTarget(
            name: "wasm",
            dependencies: [
                "veif",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit")
            ],
            swiftSettings: [
                .enableExperimentalFeature("Extern"),
                .unsafeFlags(["-Ounchecked", "-wmo", "-Xcc", "-msimd128"], .when(platforms: [.wasi]))
            ],
            plugins: [
                .plugin(name: "BridgeJS", package: "JavaScriptKit")
            ]
        )
    )
}

let package = Package(
    name: "veif",
    platforms: [
        .macOS(.v15)
    ],
    products: packageProducts,
    dependencies: packageDeps,
    targets: packageTargets,
    swiftLanguageModes: [.v6]
)
