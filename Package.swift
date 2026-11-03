// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DosMac",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DosMacCore", targets: ["DosMacCore"]), .executable(name: "DosMac", targets: ["DosMacApp"])],
    dependencies: [.package(url: "https://github.com/tsolomko/SWCompression.git", exact: "4.9.1")],
    targets: [
        .target(name: "DosMacCore", dependencies: ["SWCompression"]),
        .executableTarget(name: "DosMacApp", dependencies: ["DosMacCore"], resources: [.copy("Resources")]),
        .testTarget(name: "DosMacCoreTests", dependencies: ["DosMacCore"], resources: [.copy("Fixtures")])
    ]
)
