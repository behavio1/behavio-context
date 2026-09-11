// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaishinKit",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "HaishinKit", targets: ["HaishinKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/shogo4405/Logboard.git", "2.6.0"..<"2.7.0"),
    ],
    targets: [
        .target(
            name: "HaishinKit",
            dependencies: ["Logboard"],
            path: "Sources",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
