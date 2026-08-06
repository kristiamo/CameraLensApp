// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CameraLensPlugin",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "CameraLensPlugin",
            targets: ["CameraLensPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com", branch: "main")
    ],
    targets: [
        .target(
            name: "CameraLensPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CameraLensPlugin"),
        .testTarget(
            name: "CameraLensPluginTests",
            dependencies: ["CameraLensPlugin"],
            path: "ios/Tests")
    ]
)
