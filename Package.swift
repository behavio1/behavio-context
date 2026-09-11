// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BehavioContext",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BehavioContext", targets: ["BehavioContext"]),
        .library(name: "BehavioContextCore", targets: ["BehavioContextCore"]),
    ],
    dependencies: [
        .package(path: "Vendor/HaishinKit"),
    ],
    targets: [
        .target(
            name: "BehavioContextCore",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit"),
            ],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .executableTarget(
            name: "BehavioContext",
            dependencies: [
                "BehavioContextCore",
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "LocalizationValidationPlugin")]
        ),
        .executableTarget(
            name: "LocalizationValidator",
            path: "Tools/LocalizationValidator"
        ),
        .executableTarget(
            name: "BehavioContextChecks",
            dependencies: ["BehavioContextCore"],
            path: "Tools/BehavioContextChecks"
        ),
        .plugin(
            name: "LocalizationValidationPlugin",
            capability: .buildTool(),
            dependencies: ["LocalizationValidator"]
        ),
        .testTarget(
            name: "BehavioContextCoreTests",
            dependencies: ["BehavioContextCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
