// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NativeBolabol",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "NativeBolabol",
            targets: ["NativeBolabol"]
        ),
        .executable(
            name: "NativeBolabolPolishWorker",
            targets: ["NativeBolabolPolishWorker"]
        ),
        .library(
            name: "NativeBolabolCore",
            targets: ["NativeBolabolCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/PrismML-Eng/mlx-swift.git", branch: "prism"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", branch: "main"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "NativeBolabol",
            dependencies: [
                "NativeBolabolCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/NativeBolabol",
            exclude: [
                "Resources/AppIcon.iconset",
                "Resources/Info.plist"
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/Logos")
            ]
        ),
        .target(
            name: "NativeBolabolCore",
            path: "Sources/NativeBolabolCore"
        ),
        .executableTarget(
            name: "NativeBolabolPolishWorker",
            dependencies: [
                "NativeBolabolCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/NativeBolabolPolishWorker"
        ),
        .testTarget(
            name: "NativeBolabolCoreTests",
            dependencies: ["NativeBolabolCore", "NativeBolabol"],
            path: "Tests/NativeBolabolCoreTests"
        )
    ]
)
