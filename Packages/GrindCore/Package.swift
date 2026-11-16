// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GrindCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GrindCore", targets: ["GrindCore"])
    ],
    targets: [
        .target(name: "GrindCore"),
        .testTarget(name: "GrindCoreTests", dependencies: ["GrindCore"])
    ]
)
