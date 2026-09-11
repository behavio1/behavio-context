// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BehavioContextIntegrationTests",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "BehavioContext", path: ".."),
    ],
    targets: [
        .testTarget(
            name: "BehavioContextIntegrationTests",
            dependencies: [
                .product(name: "BehavioContextCore", package: "BehavioContext"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
