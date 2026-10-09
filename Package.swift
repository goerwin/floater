// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Floater",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Floater", targets: ["Floater"]),
        .executable(name: "FloaterCLI", targets: ["FloaterCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .target(name: "FloaterCore"),
        .executableTarget(
            name: "Floater",
            dependencies: ["FloaterCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(name: "FloaterCLI", dependencies: ["FloaterCore"]),
        .testTarget(name: "FloaterTests", dependencies: ["Floater"]),
        .testTarget(name: "FloaterCoreTests", dependencies: ["FloaterCore"])
    ],
    swiftLanguageModes: [.v6]
)
