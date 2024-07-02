// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "swiftly",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "swiftly",
            targets: ["Swiftly"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.21.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.64.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.6.1"),
    ],
    targets: [
        .executableTarget(
            name: "Swiftly",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "SwiftlyCore"),
                .target(name: "LinuxPlatform", condition: .when(platforms: [.linux])),
                .target(name: "MacOSPlatform", condition: .when(platforms: [.macOS])),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            ]
        ),
        .target(
            name: "SwiftlyCore",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
        .target(
            name: "LinuxPlatform",
            dependencies: [
                "SwiftlyCore",
                "CLibArchive",
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "MacOSPlatform",
            dependencies: [
                "SwiftlyCore",
            ]
        ),
        .systemLibrary(
            name: "CLibArchive",
            pkgConfig: "libarchive",
            providers: [
                .apt(["libarchive-dev"]),
            ]
        ),
        .testTarget(
            name: "SwiftlyTests",
            dependencies: ["Swiftly"]
        ),
    ]
)
