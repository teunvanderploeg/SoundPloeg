// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundPloeg",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SoundPloegCore", targets: ["SoundPloegCore"]),
        .library(name: "SoundPloegInfra", targets: ["SoundPloegInfra"]),
        .executable(name: "SoundPloeg", targets: ["SoundPloeg"])
    ],
    dependencies: [.package(path: "../PloegKit")],
    targets: [
        .target(
            name: "SoundPloegCore",
            dependencies: []
        ),
        .target(
            name: "SoundPloegInfra",
            dependencies: ["SoundPloegCore"],
            resources: [
                .process("Resources/model_catalog.json"),
                .copy("Resources/Runtime")
            ]
        ),
        .executableTarget(
            name: "SoundPloeg",
            dependencies: ["SoundPloegCore", "SoundPloegInfra", .product(name: "PloegKit", package: "PloegKit")],
            path: "Sources/SoundPloegApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SoundPloegCoreTests",
            dependencies: ["SoundPloegCore"]
        ),
        .testTarget(
            name: "SoundPloegIntegrationTests",
            dependencies: ["SoundPloegCore", "SoundPloegInfra"]
        ),
        .testTarget(
            name: "SoundPloegAppTests",
            dependencies: ["SoundPloeg", "SoundPloegCore", "SoundPloegInfra"]
        )
    ]
)
