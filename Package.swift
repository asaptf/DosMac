// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DosMac",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DosMacCore", targets: ["DosMacCore"]), .library(name: "DosMacVM", targets: ["DosMacVM"]), .executable(name: "DosMac", targets: ["DosMacApp"])],
    dependencies: [.package(url: "https://github.com/tsolomko/SWCompression.git", exact: "4.9.1")],
    targets: [
        .target(name: "DosMacCore", dependencies: ["SWCompression"]),
        .target(name: "DosMacVM"),
        .executableTarget(name: "DosMacApp", dependencies: ["DosMacCore", "DosMacVM"], resources: [.copy("Resources")]),
        .testTarget(name: "DosMacVMTests", dependencies: ["DosMacVM", "DosMacCore"]),
        .testTarget(name: "DosMacCoreTests", dependencies: ["DosMacCore"], resources: [.copy("Fixtures")])
    ]
)
