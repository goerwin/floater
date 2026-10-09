// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Floater",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Floater", targets: ["Floater"]),
        .executable(name: "FloaterCLI", targets: ["FloaterCLI"])
    ],
    targets: [
        .target(name: "FloaterCore"),
        .executableTarget(name: "Floater", dependencies: ["FloaterCore"]),
        .executableTarget(name: "FloaterCLI", dependencies: ["FloaterCore"]),
        .testTarget(name: "FloaterTests", dependencies: ["Floater"]),
        .testTarget(name: "FloaterCoreTests", dependencies: ["FloaterCore"])
    ],
    swiftLanguageModes: [.v6]
)
