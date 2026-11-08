// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "custom_cursor",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "custom-cursor", targets: ["custom_cursor"])
    ],
    dependencies: [
        .package(path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "custom_cursor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/custom_cursor"
        )
    ]
)