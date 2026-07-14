// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CZstd",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CZstd", type: .static, targets: ["CZstd"])
    ],
    targets: [
        .target(
            name: "CZstdC",
            path: "Vendor/zstd/lib",
            sources: ["common", "compress", "decompress"],
            publicHeadersPath: ".",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(name: "CZstd", dependencies: ["CZstdC"]),
        .testTarget(name: "CZstdTests", dependencies: ["CZstd"])
    ]
)
