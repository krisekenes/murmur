// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MurmurCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MurmurCore", targets: ["MurmurCore"])],
    targets: [
        .target(name: "MurmurCore"),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
    ]
)
