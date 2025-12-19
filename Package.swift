// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Convertify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Convertify", targets: ["Convertify"])
    ],
    dependencies: [
        .package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Convertify",
            dependencies: [
                .product(name: "FFmpegKit", package: "FFmpegKit")
            ],
            path: "Convertify",
            exclude: [
                "Info.plist",
                "Convertify.entitlements",
                "AppIcon.icon"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)

