// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
    ],
    targets: [
        .binaryTarget(
            name: "WhisperCppFramework",
            path: "Vendor/whisper.xcframework"
        ),
        .binaryTarget(
            name: "HarperFramework",
            path: "Vendor/harper.xcframework"
        ),
        .executableTarget(
            name: "Murmur",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                "WhisperCppFramework",
                "HarperFramework",
            ],
            path: "Sources/Murmur",
            resources: [
                .copy("Resources/Fonts"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
