// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DosMac",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DosMacPlatform", targets: ["DosMacPlatform"]), .library(name: "DosMacCore", targets: ["DosMacCore"]), .library(name: "DosMacVM", targets: ["DosMacVM"]), .executable(name: "DosMac", targets: ["DosMacApp"])],
    dependencies: [.package(url: "https://github.com/tsolomko/SWCompression.git", exact: "4.9.1")],
    targets: [
        .target(name: "DosMacPlatform"),
        .target(name: "DosMacCore", dependencies: ["SWCompression", "DosMacPlatform"]),
        .target(name: "DosMacVM", dependencies: ["DosMacPlatform"]),
        .executableTarget(name: "DosMacApp", dependencies: ["DosMacCore", "DosMacVM", "DosMacPlatform"], resources: [.copy("Resources")]),
        .testTarget(name: "DosMacVMTests", dependencies: ["DosMacVM", "DosMacCore"]),
        .testTarget(name: "DosMacCoreTests", dependencies: ["DosMacCore", "DosMacPlatform"], resources: [.copy("Fixtures")])
    ]
)
