// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BadmintonKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BadmintonKit", targets: ["BadmintonKit"]),
    ],
    targets: [
        .target(
            name: "BadmintonKit",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .testTarget(
            name: "BadmintonTests",
            dependencies: ["BadmintonKit"]
        ),
    ]
)
