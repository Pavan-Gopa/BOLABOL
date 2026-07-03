// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VaniScriptAppleSilicon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VaniScript",
            targets: ["VaniScript"]
        ),
        .library(
            name: "VaniScriptCore",
            targets: ["VaniScriptCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "VaniScript",
            dependencies: [
                "VaniScriptCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/VaniScript",
            resources: [.copy("Resources/Fonts")]
        ),
        .target(
            name: "VaniScriptCore",
            path: "Sources/VaniScriptCore"
        ),
        .testTarget(
            name: "VaniScriptCoreTests",
            dependencies: ["VaniScriptCore"],
            path: "Tests/VaniScriptCoreTests"
        )
    ]
)
