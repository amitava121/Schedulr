// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SchedulrLogic",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SchedulrLogic", targets: ["SchedulrLogic"])
    ],
    targets: [
        .target(
            name: "SchedulrLogic",
            path: "Sources/SchedulrLogic"
        ),
        .testTarget(
            name: "SchedulrLogicTests",
            dependencies: ["SchedulrLogic"],
            path: "Tests/SchedulrLogicTests"
        )
    ]
)
