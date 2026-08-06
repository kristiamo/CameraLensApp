// swift-tools-version: 5.9
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
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.5.0")
    ],
    targets: [
        .target(
            name: "CameraLensPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CameraLensPlugin")
    ]
)
