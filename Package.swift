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
    targets: [
        .executableTarget(
            name: "Convertify",
            path: "Convertify",
            exclude: [
                "Info.plist",
                "Convertify.entitlements"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)

