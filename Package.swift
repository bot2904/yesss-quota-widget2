// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YesssTray",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "YesssTrayApp", targets: ["YesssTrayApp"]),
    ],
    targets: [
        .executableTarget(
            name: "YesssTrayApp",
            path: "Sources/YesssTrayApp"
        ),
        .testTarget(
            name: "YesssTrayAppTests",
            dependencies: ["YesssTrayApp"],
            path: "Tests/YesssTrayAppTests"
        ),
    ]
)
