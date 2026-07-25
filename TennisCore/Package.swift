// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TennisCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TennisCore", targets: ["TennisCore"])
    ],
    targets: [
        .target(name: "TennisCore"),
        .testTarget(
            name: "TennisCoreTests",
            dependencies: ["TennisCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
