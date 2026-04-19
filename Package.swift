// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchNotify",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "NotchNotifyApp", targets: ["NotchNotifyApp"]),
        .executable(name: "notch", targets: ["notch-cli"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchNotifyApp",
            path: "Sources/NotchNotifyApp"
        ),
        .executableTarget(
            name: "notch-cli",
            path: "Sources/notch-cli"
        ),
    ]
)
